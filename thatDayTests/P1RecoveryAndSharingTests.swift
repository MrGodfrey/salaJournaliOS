import CloudKit
import UIKit
import XCTest
@testable import thatDay

final class P1RecoveryAndSharingTests: AppStoreTestCase {
    @MainActor
    func testEncryptedResetAcknowledgementSurvivesEditAndReplaysLatestOperation() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T08:00:00Z")
        let resetDate = fixtureDate("2026-07-25T08:30:00Z")
        let descriptor = RepositoryDescriptor(
            zoneName: "receipt-reset-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "receipt-reset-old-share",
            role: .owner
        )
        let recreatedDescriptor = RepositoryDescriptor(
            zoneName: "receipt-reset-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: nil,
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Receipt must survive",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Receipt Reset Owner",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "invalidated-tag"
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: snapshot],
            preferences: AppPreferences(defaultRepositoryID: repositoryID)
        )
        let deletion = CloudRepositoryZoneDeletion(
            zoneID: CloudRepositoryZoneIdentity(
                ownerName: CKCurrentUserDefaultName,
                zoneName: "receipt-reset-zone"
            ),
            reason: .encryptedDataReset
        )

        let firstCloudService = MockCloudRepositoryService()
        firstCloudService.loadedSnapshot = snapshot
        firstCloudService.metadataRecordChangeTag = "invalidated-tag"
        firstCloudService.recreateSnapshotResult = SavedRepositorySnapshot(
            descriptor: recreatedDescriptor,
            serverModifiedAt: resetDate,
            recordChangeTag: "recreated-tag"
        )
        let firstStore = AppStore(
            libraryStore: libraryStore,
            cloudService: firstCloudService,
            now: { resetDate }
        )
        await firstStore.loadIfNeeded()

        firstCloudService.recreatedSnapshots.removeAll()
        firstCloudService.recreatedDescriptors.removeAll()
        firstCloudService.deletedZonesByScope[.privateDatabase] = [deletion]
        firstCloudService.acknowledgeZoneChangesError =
            P1RecoveryTestError.acknowledgementFailed

        _ = await firstStore.handleRemoteRepositoryChange(
            .database(.privateDatabase),
            trigger: .push
        )

        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryStore.rootURL
        )
        let recoveryReceipt = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(recoveryReceipt.mode, .recreateAfterEncryptedDataReset)
        XCTAssertNotNil(recoveryReceipt.receipt)
        XCTAssertEqual(firstCloudService.recreatedSnapshots.count, 1)
        XCTAssertTrue(firstCloudService.savedSnapshots.isEmpty)
        XCTAssertEqual(
            firstCloudService.acknowledgedDeletedZonesByScope[.privateDatabase],
            [[deletion]]
        )

        firstCloudService.savedRecordChangeTag = "post-reset-edit-tag"
        let editUploadFinished = expectation(
            description: "edit after failed reset acknowledgement uploads"
        )
        firstCloudService.saveSnapshotFinishedExpectation =
            editUploadFinished
        let didSaveEdit = await firstStore.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Written before reset acknowledgement",
                body: "This generation must retain the reset chain.",
                happenedAt: resetDate.addingTimeInterval(30)
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSaveEdit)
        await fulfillment(of: [editUploadFinished], timeout: 2)
        firstCloudService.saveSnapshotFinishedExpectation = nil
        for _ in 0..<100 {
            if try outboxStore.load()?.receipt?.recordChangeTag ==
                "post-reset-edit-tag" {
                break
            }
            await Task.yield()
        }

        let editedReceipt = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(editedReceipt.mode, .normal)
        XCTAssertEqual(
            editedReceipt.receipt?.recordChangeTag,
            "post-reset-edit-tag"
        )
        XCTAssertEqual(
            editedReceipt.predecessorOperationIDs,
            [recoveryReceipt.operationID]
        )
        XCTAssertEqual(
            editedReceipt.encryptedResetAcknowledgement?.operationID,
            editedReceipt.operationID
        )
        XCTAssertEqual(
            editedReceipt.encryptedResetAcknowledgement?.receipt,
            editedReceipt.receipt
        )
        XCTAssertNotNil(
            editedReceipt.encryptedResetAcknowledgement?.attemptedAt
        )
        XCTAssertEqual(
            firstCloudService.savedExpectedRecordChangeTags,
            ["recreated-tag"]
        )
        XCTAssertEqual(
            firstCloudService.savedAcceptedPredecessorOperationIDs,
            [Set([recoveryReceipt.operationID])]
        )

        let reconstructedCloudService = MockCloudRepositoryService()
        reconstructedCloudService.loadedSnapshot = editedReceipt.snapshot
        reconstructedCloudService.metadataServerModifiedAt = resetDate
        reconstructedCloudService.metadataRecordChangeTag =
            "post-reset-edit-tag"
        reconstructedCloudService.recreateSnapshotResult =
            SavedRepositorySnapshot(
                descriptor: recreatedDescriptor,
                serverModifiedAt: resetDate,
                recordChangeTag: "post-reset-edit-tag"
            )
        reconstructedCloudService.deletedZonesByScope[.privateDatabase] = [
            deletion
        ]
        let reconstructedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: reconstructedCloudService,
            now: { resetDate.addingTimeInterval(60) }
        )

        await reconstructedStore.loadIfNeeded()

        let receiptAfterRestart = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(receiptAfterRestart.operationID, editedReceipt.operationID)
        XCTAssertEqual(receiptAfterRestart.receipt, editedReceipt.receipt)
        XCTAssertEqual(
            receiptAfterRestart.encryptedResetAcknowledgement,
            editedReceipt.encryptedResetAcknowledgement
        )
        XCTAssertTrue(reconstructedCloudService.recreatedSnapshots.isEmpty)
        XCTAssertTrue(reconstructedCloudService.savedSnapshots.isEmpty)

        _ = await reconstructedStore.handleRemoteRepositoryChange(
            .database(.privateDatabase),
            trigger: .push
        )

        XCTAssertEqual(reconstructedCloudService.recreatedSnapshots.count, 1)
        XCTAssertEqual(
            reconstructedCloudService.recreatedSnapshots.first?
                .cloudUploadOperationID,
            editedReceipt.operationID
        )
        XCTAssertEqual(
            reconstructedCloudService
                .recreatedAcceptedPredecessorOperationIDs,
            [Set(editedReceipt.predecessorOperationIDs)]
        )
        XCTAssertEqual(
            reconstructedCloudService.recreatedSnapshots.first?.entries
                .map(\.title),
            [
                "Receipt must survive",
                "Written before reset acknowledgement"
            ]
        )
        XCTAssertTrue(reconstructedCloudService.savedSnapshots.isEmpty)
        XCTAssertEqual(
            reconstructedCloudService
                .acknowledgedDeletedZonesByScope[.privateDatabase],
            [[deletion]]
        )
        XCTAssertNil(try outboxStore.load())
        let recoveredReference = try XCTUnwrap(
            libraryStore.loadCatalog().first { $0.id == repositoryID }
        )
        XCTAssertEqual(recoveredReference.descriptor, recreatedDescriptor)
        XCTAssertEqual(
            recoveredReference.lastKnownServerRecordChangeTag,
            "post-reset-edit-tag"
        )
        XCTAssertNil(recoveredReference.pendingCloudUploadGeneration)
    }

    @MainActor
    func testAcknowledgedEncryptedResetOrphanIsCleanedOnRestartBeforeNormalSave() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T08:45:00Z")
        let acknowledgementDate =
            fixtureDate("2026-07-25T09:00:00Z")
        let restartDate = fixtureDate("2026-07-25T09:15:00Z")
        let descriptor = RepositoryDescriptor(
            zoneName: "acknowledged-reset-orphan-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "acknowledged-reset-orphan-share",
            role: .owner
        )
        let recreatedDescriptor = RepositoryDescriptor(
            zoneName: descriptor.zoneName,
            zoneOwnerName: descriptor.zoneOwnerName,
            shareRecordName: nil,
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Acknowledged reset content",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Acknowledged Reset Orphan",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "invalidated-tag"
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: snapshot],
            preferences: AppPreferences(defaultRepositoryID: repositoryID)
        )
        let repositoryStore = libraryStore.repositoryStore(
            for: repositoryID
        )
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryStore.rootURL
        )
        var orphanedOutbox = try CloudUploadOutboxRecord(
            repositoryID: repositoryID,
            descriptor: descriptor,
            displayName: reference.displayName,
            snapshot: snapshot,
            generation: 4,
            baseRecordChangeTag: nil,
            mode: .recreateAfterEncryptedDataReset,
            createdAt: snapshotDate
        )
        orphanedOutbox.markUploaded(
            descriptor: recreatedDescriptor,
            serverModifiedAt: acknowledgementDate,
            recordChangeTag: "acknowledged-reset-tag",
            uploadedAt: acknowledgementDate
        )
        orphanedOutbox.markEncryptedResetAcknowledgementAttempted(
            at: acknowledgementDate
        )
        try outboxStore.save(orphanedOutbox)

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = orphanedOutbox.snapshot
        cloudService.metadataServerModifiedAt = acknowledgementDate
        cloudService.metadataRecordChangeTag =
            "acknowledged-reset-tag"
        cloudService.savedRecordChangeTag = "post-orphan-save-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { restartDate }
        )

        await store.loadIfNeeded()

        XCTAssertEqual(
            cloudService.changedZoneScopeRequests,
            [.privateDatabase]
        )
        XCTAssertNil(try outboxStore.load())
        let reconciledReference = try XCTUnwrap(
            libraryStore.loadCatalog().first { $0.id == repositoryID }
        )
        XCTAssertEqual(
            reconciledReference.lastKnownServerRecordChangeTag,
            "acknowledged-reset-tag"
        )
        XCTAssertNil(reconciledReference.pendingCloudUploadGeneration)

        let normalUploadFinished = expectation(
            description: "normal save after orphan cleanup uploads"
        )
        cloudService.saveSnapshotFinishedExpectation =
            normalUploadFinished
        let didSaveAfterCleanup = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Normal save after acknowledged reset",
                body: "The removed receipt must not block this save.",
                happenedAt: restartDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSaveAfterCleanup)
        await fulfillment(of: [normalUploadFinished], timeout: 2)
        cloudService.saveSnapshotFinishedExpectation = nil
        for _ in 0..<100 {
            if try outboxStore.load() == nil {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["acknowledged-reset-tag"]
        )
        XCTAssertEqual(
            cloudService.savedAcceptedPredecessorOperationIDs,
            [[]]
        )
        XCTAssertEqual(
            cloudService.savedSnapshots.first?.entries.last?.title,
            "Normal save after acknowledged reset"
        )
        XCTAssertNil(try outboxStore.load())
        let completedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first { $0.id == repositoryID }
        )
        XCTAssertEqual(
            completedReference.lastKnownServerRecordChangeTag,
            "post-orphan-save-tag"
        )
        XCTAssertNil(completedReference.pendingCloudUploadGeneration)
    }

    @MainActor
    func testEncryptedResetAcknowledgementSurvivesImportAndDeletionReplay() async throws {
        let rootURL = makeTempDirectory()
        let initialDate = fixtureDate("2026-07-25T09:20:00Z")
        let resetDate = fixtureDate("2026-07-25T09:30:00Z")
        let importedDate = fixtureDate("2026-07-25T09:40:00Z")
        let descriptor = RepositoryDescriptor(
            zoneName: "reset-import-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "reset-import-old-share",
            role: .owner
        )
        let recreatedDescriptor = RepositoryDescriptor(
            zoneName: descriptor.zoneName,
            zoneOwnerName: descriptor.zoneOwnerName,
            shareRecordName: nil,
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Before reset import",
                    happenedAt: initialDate
                )
            ],
            updatedAt: initialDate
        )
        let importedSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Imported after failed reset ACK",
                    happenedAt: importedDate
                )
            ],
            updatedAt: importedDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Reset Import Owner",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: initialDate,
            lastKnownServerRecordChangeTag: "invalidated-tag"
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: initialSnapshot
            ],
            preferences: AppPreferences(defaultRepositoryID: repositoryID)
        )
        let sourceStore = LocalRepositoryStore(
            rootURL: rootURL.appendingPathComponent(
                "reset-import-source",
                isDirectory: true
            )
        )
        try sourceStore.saveDescriptor(.local)
        try sourceStore.saveSnapshot(importedSnapshot)
        let archiveURL = try await RepositoryArchiveService()
            .exportArchive(
                from: sourceStore,
                repositoryID: RepositoryReference.localRepositoryID,
                repositoryName: "Reset Import Source"
            ) { _, _ in }
        let deletion = CloudRepositoryZoneDeletion(
            zoneID: CloudRepositoryZoneIdentity(
                ownerName: CKCurrentUserDefaultName,
                zoneName: "reset-import-zone"
            ),
            reason: .encryptedDataReset
        )

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "invalidated-tag"
        cloudService.recreateSnapshotResult = SavedRepositorySnapshot(
            descriptor: recreatedDescriptor,
            serverModifiedAt: resetDate,
            recordChangeTag: "reset-import-recreated-tag"
        )
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { resetDate }
        )
        await store.loadIfNeeded()

        cloudService.recreatedSnapshots.removeAll()
        cloudService.recreatedDescriptors.removeAll()
        cloudService.deletedZonesByScope[.privateDatabase] = [
            deletion
        ]
        cloudService.acknowledgeZoneChangesError =
            P1RecoveryTestError.acknowledgementFailed
        _ = await store.handleRemoteRepositoryChange(
            .database(.privateDatabase),
            trigger: .push
        )

        let repositoryStore = libraryStore.repositoryStore(
            for: repositoryID
        )
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryStore.rootURL
        )
        let recoveryOutbox = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(
            recoveryOutbox.mode,
            .recreateAfterEncryptedDataReset
        )
        XCTAssertNotNil(
            recoveryOutbox.encryptedResetAcknowledgement?.attemptedAt
        )

        cloudService.savedSnapshots.removeAll()
        cloudService.savedExpectedRecordChangeTags.removeAll()
        cloudService.savedAcceptedPredecessorOperationIDs.removeAll()
        cloudService.savedRecordChangeTag =
            "reset-import-uploaded-tag"
        let importUploadFinished = expectation(
            description: "import successor uploads"
        )
        cloudService.saveSnapshotFinishedExpectation =
            importUploadFinished

        await store.importRepositoryArchive(from: archiveURL)
        await fulfillment(of: [importUploadFinished], timeout: 2)
        cloudService.saveSnapshotFinishedExpectation = nil
        for _ in 0..<100 {
            if try outboxStore.load()?.receipt?.recordChangeTag ==
                "reset-import-uploaded-tag" {
                break
            }
            await Task.yield()
        }

        let importedOutbox = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(importedOutbox.mode, .normal)
        XCTAssertEqual(
            importedOutbox.snapshot.entries.map(\.title),
            ["Imported after failed reset ACK"]
        )
        XCTAssertEqual(
            importedOutbox.predecessorOperationIDs,
            [recoveryOutbox.operationID]
        )
        XCTAssertEqual(
            importedOutbox.encryptedResetAcknowledgement?.operationID,
            importedOutbox.operationID
        )
        XCTAssertNotNil(
            importedOutbox.encryptedResetAcknowledgement?.attemptedAt
        )
        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["reset-import-recreated-tag"]
        )
        XCTAssertEqual(
            cloudService.savedAcceptedPredecessorOperationIDs,
            [Set([recoveryOutbox.operationID])]
        )

        cloudService.acknowledgeZoneChangesError = nil
        cloudService.recreatedSnapshots.removeAll()
        cloudService.recreatedAcceptedPredecessorOperationIDs
            .removeAll()
        cloudService.savedSnapshots.removeAll()
        cloudService.recreateSnapshotResult =
            SavedRepositorySnapshot(
                descriptor: recreatedDescriptor,
                serverModifiedAt: importedDate,
                recordChangeTag: "reset-import-uploaded-tag"
            )
        _ = await store.handleRemoteRepositoryChange(
            .database(.privateDatabase),
            trigger: .push
        )

        XCTAssertTrue(cloudService.savedSnapshots.isEmpty)
        XCTAssertEqual(cloudService.recreatedSnapshots.count, 1)
        XCTAssertEqual(
            cloudService.recreatedSnapshots.first?
                .cloudUploadOperationID,
            importedOutbox.operationID
        )
        XCTAssertEqual(
            cloudService.recreatedSnapshots.first?.entries.map(\.title),
            ["Imported after failed reset ACK"]
        )
        XCTAssertEqual(
            cloudService.recreatedAcceptedPredecessorOperationIDs,
            [Set(importedOutbox.predecessorOperationIDs)]
        )
        XCTAssertEqual(
            cloudService.acknowledgedDeletedZonesByScope[
                .privateDatabase
            ],
            [[deletion], [deletion]]
        )
        XCTAssertNil(try outboxStore.load())
        let completedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first { $0.id == repositoryID }
        )
        XCTAssertEqual(
            completedReference.lastKnownServerRecordChangeTag,
            "reset-import-uploaded-tag"
        )
        XCTAssertNil(completedReference.pendingCloudUploadGeneration)
    }

    @MainActor
    func testResetDeletionWaitsForDurableLocalReceiptCommit() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T09:45:00Z")
        let resetDate = fixtureDate("2026-07-25T10:00:00Z")
        let descriptor = RepositoryDescriptor(
            zoneName: "reset-local-commit-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "reset-local-commit-old-share",
            role: .owner
        )
        let recreatedDescriptor = RepositoryDescriptor(
            zoneName: descriptor.zoneName,
            zoneOwnerName: descriptor.zoneOwnerName,
            shareRecordName: nil,
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Receipt must commit locally",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Reset Local Commit",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "invalidated-tag"
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: snapshot],
            preferences: AppPreferences(defaultRepositoryID: repositoryID)
        )
        let deletion = CloudRepositoryZoneDeletion(
            zoneID: CloudRepositoryZoneIdentity(
                ownerName: CKCurrentUserDefaultName,
                zoneName: "reset-local-commit-zone"
            ),
            reason: .encryptedDataReset
        )
        let firstCloudService = MockCloudRepositoryService()
        firstCloudService.loadedSnapshot = snapshot
        firstCloudService.metadataRecordChangeTag = "invalidated-tag"
        firstCloudService.recreateSnapshotResult =
            SavedRepositorySnapshot(
                descriptor: recreatedDescriptor,
                serverModifiedAt: resetDate,
                recordChangeTag: "reset-local-commit-tag"
            )
        let firstStore = AppStore(
            libraryStore: libraryStore,
            cloudService: firstCloudService,
            now: { resetDate }
        )
        await firstStore.loadIfNeeded()

        firstCloudService.recreatedSnapshots.removeAll()
        firstCloudService.pauseRecreateSnapshot = true
        firstCloudService.recreateSnapshotStartedExpectation =
            expectation(
                description: "reset upload pauses before receipt"
            )
        firstCloudService.deletedZonesByScope[.privateDatabase] = [
            deletion
        ]
        let resetTask = Task { @MainActor in
            await firstStore.handleRemoteRepositoryChange(
                .database(.privateDatabase),
                trigger: .push
            )
        }
        if let uploadStarted =
            firstCloudService.recreateSnapshotStartedExpectation {
            await fulfillment(of: [uploadStarted], timeout: 2)
        }

        let catalogBackupURL = rootURL.appendingPathComponent(
            "repositories-before-reset-commit.json"
        )
        try FileManager.default.moveItem(
            at: libraryStore.catalogURL,
            to: catalogBackupURL
        )
        try FileManager.default.createDirectory(
            at: libraryStore.catalogURL,
            withIntermediateDirectories: false
        )
        firstCloudService.resumePausedRecreateSnapshot()
        _ = await resetTask.value

        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore.repositoryStore(
                for: repositoryID
            ).rootURL
        )
        let uncommittedReceipt = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(
            uncommittedReceipt.receipt?.recordChangeTag,
            "reset-local-commit-tag"
        )
        XCTAssertNil(
            uncommittedReceipt.encryptedResetAcknowledgement?
                .attemptedAt
        )
        XCTAssertTrue(
            firstCloudService
                .acknowledgedDeletedZonesByScope[.privateDatabase]?
                .isEmpty ?? true
        )

        try FileManager.default.removeItem(
            at: libraryStore.catalogURL
        )
        try FileManager.default.moveItem(
            at: catalogBackupURL,
            to: libraryStore.catalogURL
        )
        let staleReference = try XCTUnwrap(
            libraryStore.loadCatalog().first { $0.id == repositoryID }
        )
        XCTAssertEqual(
            staleReference.lastKnownServerRecordChangeTag,
            "invalidated-tag"
        )
        XCTAssertEqual(
            staleReference.pendingCloudUploadGeneration,
            uncommittedReceipt.generation
        )

        let reconstructedCloudService =
            MockCloudRepositoryService()
        reconstructedCloudService.loadedSnapshot =
            uncommittedReceipt.snapshot
        reconstructedCloudService.metadataServerModifiedAt = resetDate
        reconstructedCloudService.metadataRecordChangeTag =
            "reset-local-commit-tag"
        reconstructedCloudService.recreateSnapshotResult =
            SavedRepositorySnapshot(
                descriptor: recreatedDescriptor,
                serverModifiedAt: resetDate,
                recordChangeTag: "reset-local-commit-tag"
            )
        reconstructedCloudService.deletedZonesByScope[
            .privateDatabase
        ] = [deletion]
        let reconstructedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: reconstructedCloudService,
            now: { resetDate.addingTimeInterval(60) }
        )

        await reconstructedStore.loadIfNeeded()

        let committedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first { $0.id == repositoryID }
        )
        XCTAssertEqual(
            committedReference.descriptor,
            recreatedDescriptor
        )
        XCTAssertEqual(
            committedReference.lastKnownServerRecordChangeTag,
            "reset-local-commit-tag"
        )
        XCTAssertNil(committedReference.pendingCloudUploadGeneration)
        XCTAssertNotNil(try outboxStore.load())
        XCTAssertTrue(
            reconstructedCloudService
                .acknowledgedDeletedZonesByScope[.privateDatabase]?
                .isEmpty ?? true
        )

        _ = await reconstructedStore.handleRemoteRepositoryChange(
            .database(.privateDatabase),
            trigger: .push
        )

        XCTAssertEqual(
            reconstructedCloudService.recreatedSnapshots.first?
                .cloudUploadOperationID,
            uncommittedReceipt.operationID
        )
        XCTAssertEqual(
            reconstructedCloudService
                .acknowledgedDeletedZonesByScope[.privateDatabase],
            [[deletion]]
        )
        XCTAssertNil(try outboxStore.load())
    }

    @MainActor
    func testEncryptedResetSerializesConcurrentNewGenerationAndUploadsLatestContent() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T09:00:00Z")
        let resetDate = fixtureDate("2026-07-25T09:30:00Z")
        let descriptor = RepositoryDescriptor(
            zoneName: "concurrent-reset-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "concurrent-reset-share",
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Before reset",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Concurrent Reset Owner",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "invalidated-tag"
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: initialSnapshot],
            preferences: AppPreferences(defaultRepositoryID: repositoryID)
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "invalidated-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { resetDate }
        )
        await store.loadIfNeeded()

        cloudService.recreatedSnapshots.removeAll()
        cloudService.savedSnapshots.removeAll()
        cloudService.savedDescriptors.removeAll()
        cloudService.pauseRecreateSnapshot = true
        cloudService.recreateSnapshotStartedExpectation = expectation(
            description: "reset recreation is paused"
        )
        cloudService.recreateSnapshotResult = SavedRepositorySnapshot(
            descriptor: descriptor,
            serverModifiedAt: resetDate,
            recordChangeTag: "recreated-baseline-tag"
        )
        let deletion = CloudRepositoryZoneDeletion(
            zoneID: CloudRepositoryZoneIdentity(
                ownerName: CKCurrentUserDefaultName,
                zoneName: "concurrent-reset-zone"
            ),
            reason: .encryptedDataReset
        )
        cloudService.deletedZonesByScope[.privateDatabase] = [deletion]

        let resetTask = Task { @MainActor in
            await store.handleRemoteRepositoryChange(
                .database(.privateDatabase),
                trigger: .push
            )
        }
        if let expectation = cloudService.recreateSnapshotStartedExpectation {
            await fulfillment(of: [expectation], timeout: 2)
        }

        let didSaveNewGeneration = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Written while reset is in flight",
                body: "This generation must be uploaded after recreation.",
                happenedAt: resetDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSaveNewGeneration)

        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: repositoryID)
                .rootURL
        )
        let concurrentOutbox = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(concurrentOutbox.mode, .recreateAfterEncryptedDataReset)
        XCTAssertTrue(
            concurrentOutbox.snapshot.entries.contains {
                $0.title == "Written while reset is in flight"
            }
        )
        XCTAssertEqual(concurrentOutbox.predecessorOperationIDs.count, 1)

        cloudService.resumePausedRecreateSnapshot()
        _ = await resetTask.value

        XCTAssertEqual(cloudService.recreatedSnapshots.count, 1)
        XCTAssertEqual(cloudService.savedSnapshots.count, 1)
        XCTAssertEqual(cloudService.savedDescriptors, [descriptor])
        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["recreated-baseline-tag"]
        )
        XCTAssertEqual(
            cloudService.savedAcceptedPredecessorOperationIDs,
            [Set(concurrentOutbox.predecessorOperationIDs)]
        )
        XCTAssertTrue(
            try XCTUnwrap(cloudService.savedSnapshots.first).entries.contains {
                $0.title == "Written while reset is in flight"
            }
        )
        XCTAssertEqual(
            cloudService.acknowledgedDeletedZonesByScope[.privateDatabase],
            [[deletion]]
        )
        XCTAssertNil(try outboxStore.load())
        XCTAssertNil(
            try libraryStore.loadCatalog()
                .first { $0.id == repositoryID }?
                .pendingCloudUploadGeneration
        )
    }

    @MainActor
    func testPurgeTombstoneCompletesCleanupAfterRestartWithoutRebuildingOutbox() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T10:00:00Z")
        let purgeDate = fixtureDate("2026-07-25T10:30:00Z")
        let descriptor = RepositoryDescriptor(
            zoneName: "restart-purge-zone",
            zoneOwnerName: "_restart_purge_owner_",
            shareRecordName: "restart-purge-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Must be purged after restart",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Restart Purge",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "purged-tag",
            pendingCloudUploadAt: purgeDate,
            pendingCloudUploadGeneration: 4,
            pendingCloudUploadBaseChangeTag: "purged-tag",
            cloudPurgeRequestedAt: purgeDate
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: snapshot],
            preferences: AppPreferences(defaultRepositoryID: repositoryID)
        )
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryStore.rootURL
        )
        try outboxStore.save(
            CloudUploadOutboxRecord(
                repositoryID: repositoryID,
                descriptor: descriptor,
                displayName: "Restart Purge",
                snapshot: snapshot,
                generation: 4,
                baseRecordChangeTag: "purged-tag",
                createdAt: purgeDate
            )
        )
        XCTAssertNotNil(try outboxStore.load())

        let firstCloudService = MockCloudRepositoryService()
        let firstStore = AppStore(
            libraryStore: libraryStore,
            cloudService: firstCloudService,
            now: { purgeDate.addingTimeInterval(60) }
        )
        await firstStore.loadIfNeeded()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: repositoryStore.rootURL.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outboxStore.fileURL.path)
        )
        XCTAssertNil(
            try libraryStore.loadCatalog().first { $0.id == repositoryID }
        )
        XCTAssertEqual(
            try libraryStore.loadPreferences().defaultRepositoryID,
            RepositoryReference.localRepositoryID
        )
        XCTAssertEqual(
            firstStore.currentRepositoryID,
            RepositoryReference.localRepositoryID
        )
        XCTAssertTrue(firstCloudService.savedSnapshots.isEmpty)
        XCTAssertTrue(firstCloudService.recreatedSnapshots.isEmpty)

        let secondCloudService = MockCloudRepositoryService()
        let secondStore = AppStore(
            libraryStore: libraryStore,
            cloudService: secondCloudService,
            now: { purgeDate.addingTimeInterval(120) }
        )
        await secondStore.loadIfNeeded()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: repositoryStore.rootURL.path)
        )
        XCTAssertNil(try outboxStore.load())
        XCTAssertNil(
            try libraryStore.loadCatalog().first { $0.id == repositoryID }
        )
        XCTAssertTrue(secondCloudService.savedSnapshots.isEmpty)
        XCTAssertTrue(secondCloudService.recreatedSnapshots.isEmpty)
    }

    @MainActor
    func testLocalSharePersistsPrepareShareOutboxBeforeUnifiedQueueUploads() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T11:00:00Z")
        let localSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Durable before sharing",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            localSnapshot: localSnapshot
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.pauseSaveSnapshot = true
        cloudService.saveSnapshotStartedExpectation = expectation(
            description: "prepare-share upload is paused"
        )
        cloudService.savedRecordChangeTag = "prepare-share-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate.addingTimeInterval(60) }
        )
        await store.loadIfNeeded()

        let sharingTask = Task { @MainActor in
            await store.presentSharingController()
        }
        if let expectation = cloudService.saveSnapshotStartedExpectation {
            await fulfillment(of: [expectation], timeout: 2)
        }
        cloudService.saveSnapshotStartedExpectation = nil

        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: RepositoryReference.localRepositoryID)
                .rootURL
        )
        let durableOutbox = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(durableOutbox.mode, .prepareShare)
        XCTAssertEqual(durableOutbox.descriptor, .local)
        XCTAssertNil(durableOutbox.receipt)
        XCTAssertEqual(cloudService.savedDescriptors, [.local])
        XCTAssertTrue(cloudService.sharingControllerDescriptors.isEmpty)
        XCTAssertNil(store.sharingControllerItem)
        let pendingReference = try XCTUnwrap(
            libraryStore.loadCatalog().first {
                $0.id == RepositoryReference.localRepositoryID
            }
        )
        XCTAssertEqual(
            pendingReference.pendingCloudUploadGeneration,
            durableOutbox.generation
        )

        cloudService.resumePausedSaveSnapshot()
        await sharingTask.value

        XCTAssertEqual(cloudService.savedSnapshots, [durableOutbox.snapshot])
        XCTAssertEqual(cloudService.savedExpectedRecordChangeTags, [nil])
        XCTAssertEqual(cloudService.savedAcceptedPredecessorOperationIDs, [[]])
        XCTAssertEqual(cloudService.sharingControllerDescriptors.count, 1)
        XCTAssertEqual(
            cloudService.sharingControllerDescriptors.first?.role,
            .owner
        )
        XCTAssertNotNil(store.sharingControllerItem)
        XCTAssertNil(try outboxStore.load())
        let ownerReference = try XCTUnwrap(
            libraryStore.loadCatalog().first {
                $0.id == RepositoryReference.localRepositoryID
            }
        )
        XCTAssertEqual(ownerReference.descriptor.role, .owner)
        XCTAssertNil(ownerReference.pendingCloudUploadGeneration)
    }

    @MainActor
    func testLocalMutationDuringPrepareShareCreatesAndUploadsNextGeneration() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T11:30:00Z")
        let mutationDate = snapshotDate.addingTimeInterval(60)
        let localSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Before sharing",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            localSnapshot: localSnapshot
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.pauseSaveSnapshot = true
        cloudService.saveSnapshotStartedExpectation = expectation(
            description: "first prepare-share generation is paused"
        )
        cloudService.savedRecordChangeTag = "prepare-share-baseline"
        let currentDate = snapshotDate.addingTimeInterval(30)
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { currentDate }
        )
        await store.loadIfNeeded()

        let sharingTask = Task { @MainActor in
            await store.presentSharingController()
        }
        if let expectation = cloudService.saveSnapshotStartedExpectation {
            await fulfillment(of: [expectation], timeout: 2)
        }

        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: RepositoryReference.localRepositoryID)
                .rootURL
        )
        let firstGeneration = try XCTUnwrap(outboxStore.load())
        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Written while share preparation is uploading",
                body: "This content must become the next durable generation.",
                happenedAt: mutationDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSave)

        let nextGeneration = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(nextGeneration.mode, .prepareShare)
        XCTAssertEqual(nextGeneration.generation, firstGeneration.generation + 1)
        XCTAssertEqual(
            nextGeneration.predecessorOperationIDs,
            [firstGeneration.operationID]
        )
        XCTAssertTrue(
            nextGeneration.snapshot.entries.contains {
                $0.title == "Written while share preparation is uploading"
            }
        )
        XCTAssertEqual(
            try libraryStore.loadCatalog().first {
                $0.id == RepositoryReference.localRepositoryID
            }?.pendingCloudUploadGeneration,
            nextGeneration.generation
        )

        let secondUploadStarted = expectation(
            description: "next prepare-share generation starts"
        )
        cloudService.saveSnapshotStartedExpectation = secondUploadStarted
        cloudService.resumePausedSaveSnapshot()
        await fulfillment(of: [secondUploadStarted], timeout: 2)
        cloudService.saveSnapshotStartedExpectation = nil
        await sharingTask.value

        XCTAssertEqual(cloudService.savedSnapshots.count, 2)
        XCTAssertTrue(
            try XCTUnwrap(cloudService.savedSnapshots.last).entries.contains {
                $0.title == "Written while share preparation is uploading"
            }
        )
        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            [nil, "prepare-share-baseline"]
        )
        XCTAssertNil(try outboxStore.load())
        XCTAssertNil(
            try libraryStore.loadCatalog().first {
                $0.id == RepositoryReference.localRepositoryID
            }?.pendingCloudUploadGeneration
        )
        XCTAssertTrue(
            try XCTUnwrap(cloudService.sharingControllerSnapshots.first)
                .entries
                .contains {
                    $0.title == "Written while share preparation is uploading"
                }
        )
        XCTAssertEqual(
            try libraryStore.repositoryStore(
                for: RepositoryReference.localRepositoryID
            ).loadSnapshot()?.entries.filter {
                $0.title == "Written while share preparation is uploading"
            }.count,
            1
        )
    }

    @MainActor
    func testPreparedShareSuccessorRecoversIfAppStopsBeforeCatalogPromotion() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate(
            "2026-07-25T12:00:00Z"
        )
        let successorSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Successor after share creation",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            localSnapshot: successorSnapshot,
            preferences: AppPreferences(
                cloudAccountUserRecordName:
                    "mock-cloud-account"
            )
        )
        let ownerDescriptor = RepositoryDescriptor(
            zoneName: "prepared-share-successor-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "prepared-share-successor-share",
            role: .owner
        )
        let preparationReceipt = CloudUploadReceipt(
            descriptor: ownerDescriptor,
            serverModifiedAt: snapshotDate,
            recordChangeTag: "prepared-share-tag",
            uploadedAt: snapshotDate
        )
        var successorOutbox = try CloudUploadOutboxRecord(
            repositoryID:
                RepositoryReference.localRepositoryID,
            descriptor: .local,
            displayName: "My Repository",
            snapshot: successorSnapshot,
            generation: 2,
            baseRecordChangeTag: nil,
            baseSnapshot: RepositorySnapshot(
                entries: [],
                updatedAt:
                    snapshotDate.addingTimeInterval(-60)
            ),
            predecessorOperationIDs: [UUID()],
            mode: .prepareShare,
            createdAt: snapshotDate
        )
        try successorOutbox.advanceBaseRecordChangeTag(
            preparationReceipt.recordChangeTag,
            baseSnapshot: successorSnapshot
        )
        successorOutbox.mode = .normal
        successorOutbox.descriptor = ownerDescriptor
        successorOutbox.recordSharePreparationReceipt(
            preparationReceipt
        )
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(
                    for:
                        RepositoryReference.localRepositoryID
                )
                .rootURL
        )
        try outboxStore.save(successorOutbox)
        var catalog = try libraryStore.loadCatalog()
        let localIndex = try XCTUnwrap(
            catalog.firstIndex {
                $0.id ==
                    RepositoryReference.localRepositoryID
            }
        )
        catalog[localIndex].pendingCloudUploadAt =
            snapshotDate
        catalog[localIndex].pendingCloudUploadGeneration =
            successorOutbox.generation
        try libraryStore.saveCatalog(catalog)

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = successorSnapshot
        cloudService.metadataRecordChangeTag =
            "successor-upload-tag"
        cloudService.savedRecordChangeTag =
            "successor-upload-tag"
        let restartedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: {
                snapshotDate.addingTimeInterval(60)
            }
        )

        await restartedStore.loadIfNeeded()

        XCTAssertEqual(
            cloudService.savedDescriptors,
            [ownerDescriptor]
        )
        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["prepared-share-tag"]
        )
        XCTAssertNil(try outboxStore.load())
        let recoveredReference = try XCTUnwrap(
            libraryStore.loadCatalog().first {
                $0.id ==
                    RepositoryReference.localRepositoryID
            }
        )
        XCTAssertEqual(
            recoveredReference.descriptor,
            ownerDescriptor
        )
        XCTAssertNil(
            recoveredReference.pendingCloudUploadGeneration
        )
        XCTAssertEqual(
            try libraryStore.repositoryStore(
                for:
                    RepositoryReference.localRepositoryID
            ).loadDescriptor(),
            ownerDescriptor
        )
    }

    @MainActor
    func testEncryptedResetWithoutLocalSnapshotStaysPendingAndDoesNotPublishEmptyRepository() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T13:00:00Z")
        let descriptor = RepositoryDescriptor(
            zoneName: "missing-reset-snapshot-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "missing-reset-snapshot-share",
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let remoteSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Remote launch fixture",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Missing Reset Snapshot",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "before-reset-tag"
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            references: [reference]
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = remoteSnapshot
        cloudService.metadataRecordChangeTag = "before-reset-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate.addingTimeInterval(60) }
        )
        await store.loadIfNeeded()

        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        try FileManager.default.removeItem(at: repositoryStore.archiveURL)
        cloudService.recreatedSnapshots.removeAll()
        cloudService.deletedZonesByScope[.privateDatabase] = [
            encryptedResetDeletion(for: descriptor)
        ]

        let result = await store.handleRemoteRepositoryChange(
            .database(.privateDatabase),
            trigger: .push
        )

        XCTAssertEqual(result.rawValue, UIBackgroundFetchResult.failed.rawValue)
        XCTAssertTrue(cloudService.recreatedSnapshots.isEmpty)
        XCTAssertTrue(
            cloudService
                .acknowledgedDeletedZonesByScope[.privateDatabase, default: []]
                .isEmpty
        )
        XCTAssertNil(
            try CloudUploadOutboxStore(
                repositoryRootURL: repositoryStore.rootURL
            ).load()
        )
    }

    @MainActor
    func testEncryptedResetWithMissingReferencedImageStaysPending() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T13:30:00Z")
        let descriptor = RepositoryDescriptor(
            zoneName: "missing-reset-image-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "missing-reset-image-share",
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        var entry = makeEntry(
            kind: .blog,
            title: "Image must not disappear",
            happenedAt: snapshotDate
        )
        entry.imageReference = "missing-reset-image.jpg"
        let snapshot = RepositorySnapshot(
            entries: [entry],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Missing Reset Image",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "before-image-reset-tag"
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: snapshot]
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = snapshot
        cloudService.metadataRecordChangeTag = "before-image-reset-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate.addingTimeInterval(60) }
        )
        await store.loadIfNeeded()

        cloudService.recreatedSnapshots.removeAll()
        cloudService.deletedZonesByScope[.privateDatabase] = [
            encryptedResetDeletion(for: descriptor)
        ]

        let result = await store.handleRemoteRepositoryChange(
            .database(.privateDatabase),
            trigger: .push
        )

        XCTAssertEqual(result.rawValue, UIBackgroundFetchResult.failed.rawValue)
        XCTAssertTrue(cloudService.recreatedSnapshots.isEmpty)
        XCTAssertTrue(
            cloudService
                .acknowledgedDeletedZonesByScope[.privateDatabase, default: []]
                .isEmpty
        )
        XCTAssertNil(
            try CloudUploadOutboxStore(
                repositoryRootURL: libraryStore
                    .repositoryStore(for: repositoryID)
                    .rootURL
            ).load()
        )
    }

    @MainActor
    func testThrottledBackgroundRecoveryDoesNotRecordFalseFullRefresh() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T14:00:00Z")
        let lastRefreshDate = snapshotDate.addingTimeInterval(-3_600)
        let currentDate = snapshotDate.addingTimeInterval(60)
        let throttleUntil = currentDate.addingTimeInterval(120)
        let descriptor = RepositoryDescriptor(
            zoneName: "throttled-recovery-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "throttled-recovery-share",
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Must still be checked after throttle",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Throttled Recovery",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "throttled-tag"
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: snapshot],
            preferences: AppPreferences(
                cloudRetryAfter: throttleUntil,
                lastSuccessfulCloudRefreshAt: lastRefreshDate
            )
        )
        let cloudService = MockCloudRepositoryService()
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { currentDate }
        )
        await store.loadIfNeeded()

        let result = await store.handleRemoteRepositoryChange(
            nil,
            trigger: .backgroundRecovery
        )

        XCTAssertEqual(result.rawValue, UIBackgroundFetchResult.noData.rawValue)
        XCTAssertTrue(cloudService.changedZoneScopeRequests.isEmpty)
        XCTAssertEqual(
            try libraryStore.loadPreferences()
                .lastSuccessfulCloudRefreshAt,
            lastRefreshDate
        )
    }

    @MainActor
    func testFailedLocalShareOutboxResumesOnRestart() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-25T12:00:00Z")
        let localSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Recover share upload after restart",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let libraryStore = try makeLibrary(
            rootURL: rootURL,
            localSnapshot: localSnapshot
        )
        let firstCloudService = MockCloudRepositoryService()
        firstCloudService.saveSnapshotError =
            P1RecoveryTestError.uploadFailed
        let firstStore = AppStore(
            libraryStore: libraryStore,
            cloudService: firstCloudService,
            now: { snapshotDate.addingTimeInterval(60) }
        )
        await firstStore.loadIfNeeded()

        await firstStore.presentSharingController()

        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: RepositoryReference.localRepositoryID)
                .rootURL
        )
        let failedOutbox = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(failedOutbox.mode, .prepareShare)
        XCTAssertNil(failedOutbox.receipt)
        XCTAssertNil(firstStore.sharingControllerItem)
        XCTAssertTrue(firstCloudService.sharingControllerDescriptors.isEmpty)
        XCTAssertEqual(firstCloudService.savedSnapshots, [failedOutbox.snapshot])
        let failedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first {
                $0.id == RepositoryReference.localRepositoryID
            }
        )
        XCTAssertEqual(
            failedReference.pendingCloudUploadGeneration,
            failedOutbox.generation
        )
        XCTAssertEqual(failedReference.descriptor, .local)

        let reconstructedCloudService = MockCloudRepositoryService()
        reconstructedCloudService.savedRecordChangeTag = "recovered-share-tag"
        reconstructedCloudService.metadataRecordChangeTag =
            "recovered-share-tag"
        reconstructedCloudService.loadedSnapshot = failedOutbox.snapshot
        let reconstructedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: reconstructedCloudService,
            now: { snapshotDate.addingTimeInterval(120) }
        )

        await reconstructedStore.loadIfNeeded()

        XCTAssertEqual(
            reconstructedCloudService.savedSnapshots,
            [failedOutbox.snapshot]
        )
        XCTAssertEqual(reconstructedCloudService.savedDescriptors, [.local])
        XCTAssertEqual(
            reconstructedCloudService.savedExpectedRecordChangeTags,
            [nil]
        )
        XCTAssertNil(try outboxStore.load())
        let recoveredReference = try XCTUnwrap(
            libraryStore.loadCatalog().first {
                $0.id == RepositoryReference.localRepositoryID
            }
        )
        XCTAssertEqual(recoveredReference.descriptor.role, .owner)
        XCTAssertEqual(
            recoveredReference.lastKnownServerRecordChangeTag,
            "recovered-share-tag"
        )
        XCTAssertNil(recoveredReference.pendingCloudUploadGeneration)
        XCTAssertTrue(
            reconstructedCloudService.sharingControllerDescriptors.isEmpty
        )
    }

    private func makeLibrary(
        rootURL: URL,
        localSnapshot: RepositorySnapshot = RepositorySnapshot(entries: []),
        references: [RepositoryReference] = [],
        snapshotsByRepositoryID: [String: RepositorySnapshot] = [:],
        preferences: AppPreferences = AppPreferences()
    ) throws -> RepositoryLibraryStore {
        let libraryStore = RepositoryLibraryStore(rootURL: rootURL)
        let localStore = libraryStore.repositoryStore(
            for: RepositoryReference.localRepositoryID
        )
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(localSnapshot)

        for reference in references {
            let repositoryStore = libraryStore.repositoryStore(for: reference.id)
            try repositoryStore.saveDescriptor(reference.descriptor)
            if let snapshot = snapshotsByRepositoryID[reference.id] {
                try repositoryStore.saveSnapshot(snapshot)
            }
        }

        try libraryStore.saveCatalog([RepositoryReference.local] + references)
        try libraryStore.savePreferences(preferences)
        return libraryStore
    }

    private func encryptedResetDeletion(
        for descriptor: RepositoryDescriptor
    ) -> CloudRepositoryZoneDeletion {
        CloudRepositoryZoneDeletion(
            zoneID: CloudRepositoryZoneIdentity(
                ownerName: descriptor.zoneOwnerName ?? CKCurrentUserDefaultName,
                zoneName: descriptor.zoneName ?? ""
            ),
            reason: .encryptedDataReset
        )
    }
}

private enum P1RecoveryTestError: Error {
    case acknowledgementFailed
    case uploadFailed
}
