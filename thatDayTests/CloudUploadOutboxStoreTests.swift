import CryptoKit
import Foundation
import XCTest
@testable import thatDay

final class CloudUploadOutboxStoreTests: AppStoreTestCase {
    func testOutboxRejectsSnapshotWithMissingEmbeddedImage() throws {
        let snapshotDate = fixtureDate("2026-07-25T08:30:00Z")
        var availableEntry = makeEntry(
            kind: .blog,
            title: "Complete image payload",
            happenedAt: snapshotDate
        )
        availableEntry.imageReference = "available-image.jpg"
        var missingEntry = makeEntry(
            kind: .blog,
            title: "Incomplete image payload",
            happenedAt: snapshotDate
        )
        missingEntry.imageReference = "missing-image.jpg"

        XCTAssertThrowsError(
            try CloudUploadOutboxRecord(
                repositoryID: "missing-image-repository",
                descriptor: .local,
                displayName: "Missing Image",
                snapshot: RepositorySnapshot(
                    entries: [availableEntry, missingEntry],
                    updatedAt: snapshotDate,
                    embeddedImages: [
                        RepositoryImageAsset(
                            reference: "available-image.jpg",
                            data: Data("available".utf8)
                        )
                    ]
                ),
                generation: 1,
                baseRecordChangeTag: nil,
                createdAt: snapshotDate
            )
        ) { error in
            guard let cloudError = error as? CloudRepositoryError else {
                return XCTFail("Expected CloudRepositoryError")
            }
            guard case .invalidRepositoryData = cloudError else {
                return XCTFail("Expected invalidRepositoryData")
            }
        }
    }

    func testAtomicSaveReloadsCompleteEmbeddedSnapshotAndValidatesDigest() throws {
        let repositoryRootURL = makeTempDirectory()
            .appendingPathComponent("repository", isDirectory: true)
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryRootURL
        )
        let descriptor = RepositoryDescriptor(
            zoneName: "atomic-outbox-zone",
            zoneOwnerName: "_atomic_outbox_owner_",
            shareRecordName: "atomic-outbox-share",
            role: .editor
        )
        let entryID = UUID()
        let imageReference = "\(entryID.uuidString).jpg"
        let imageData = Data((0...255).map { UInt8($0) })
        let initialDate = fixtureDate("2026-07-25T09:00:00Z")
        let replacementDate = fixtureDate("2026-07-25T10:00:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "Initial outbox snapshot",
                    body: "Initial body",
                    happenedAt: initialDate,
                    createdAt: initialDate,
                    updatedAt: initialDate,
                    imageReference: imageReference
                )
            ],
            updatedAt: initialDate,
            embeddedImages: [
                RepositoryImageAsset(
                    reference: imageReference,
                    data: imageData
                )
            ],
            blogTags: ["Outbox"],
            sharedUpdateNotificationScope: .all
        )
        let initialRecord = try CloudUploadOutboxRecord(
            repositoryID: descriptor.storageIdentifier,
            descriptor: descriptor,
            displayName: "Atomic Outbox",
            snapshot: initialSnapshot,
            generation: 40,
            baseRecordChangeTag: "baseline-40",
            createdAt: initialDate
        )

        try outboxStore.save(initialRecord)

        let initiallyReloaded = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(initiallyReloaded, initialRecord)
        XCTAssertEqual(initiallyReloaded.snapshot.embeddedImages.count, 1)
        XCTAssertEqual(initiallyReloaded.snapshot.embeddedImages.first?.data, imageData)
        XCTAssertEqual(initiallyReloaded.generation, 40)
        XCTAssertEqual(initiallyReloaded.baseRecordChangeTag, "baseline-40")

        var replacementEntry = try XCTUnwrap(initialSnapshot.entries.first)
        replacementEntry.title = "Atomically replaced outbox snapshot"
        replacementEntry.body = "Replacement body"
        replacementEntry.updatedAt = replacementDate
        let replacementSnapshot = RepositorySnapshot(
            entries: [replacementEntry],
            updatedAt: replacementDate,
            embeddedImages: initialSnapshot.embeddedImages,
            blogTags: initialSnapshot.blogTags,
            sharedUpdateNotificationScope: initialSnapshot.sharedUpdateNotificationScope
        )
        let replacementRecord = try CloudUploadOutboxRecord(
            repositoryID: descriptor.storageIdentifier,
            descriptor: descriptor,
            displayName: "Atomic Outbox",
            snapshot: replacementSnapshot,
            generation: 41,
            baseRecordChangeTag: "baseline-40",
            createdAt: replacementDate
        )

        try outboxStore.save(replacementRecord)

        let reloaded = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(reloaded, replacementRecord)
        XCTAssertEqual(
            reloaded.snapshot,
            replacementRecord.snapshot
        )
        XCTAssertEqual(reloaded.snapshot.embeddedImages.first?.data, imageData)
        XCTAssertEqual(reloaded.generation, 41)
        XCTAssertEqual(reloaded.baseRecordChangeTag, "baseline-40")
        XCTAssertNotEqual(reloaded.contentDigest, initiallyReloaded.contentDigest)
        XCTAssertEqual(reloaded.contentDigest.count, 64)
        XCTAssertTrue(
            reloaded.contentDigest.allSatisfy {
                $0.isNumber || ("a"..."f").contains(String($0))
            }
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: repositoryRootURL,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent),
            ["pending-cloud-upload.json"]
        )

        var tamperedRecord = reloaded
        tamperedRecord.snapshot.entries[0].body = "Changed without updating the digest"
        try outboxStore.save(tamperedRecord)

        XCTAssertThrowsError(try outboxStore.load()) { error in
            XCTAssertTrue(error is CloudRepositoryError)
        }
    }

    func testUploadReceiptPersistsAcrossOutboxStoreReconstruction() throws {
        let repositoryRootURL = makeTempDirectory()
            .appendingPathComponent("repository", isDirectory: true)
        let descriptor = RepositoryDescriptor(
            zoneName: "receipt-zone",
            zoneOwnerName: "_receipt_owner_",
            shareRecordName: "receipt-share",
            role: .editor
        )
        let savedDescriptor = RepositoryDescriptor(
            zoneName: "receipt-zone",
            zoneOwnerName: "_receipt_owner_",
            shareRecordName: "receipt-share",
            role: .owner
        )
        let snapshotDate = fixtureDate("2026-07-25T11:00:00Z")
        let uploadedAt = fixtureDate("2026-07-25T11:05:00Z")
        let serverModifiedAt = fixtureDate("2026-07-25T11:04:30Z")
        var record = try CloudUploadOutboxRecord(
            repositoryID: descriptor.storageIdentifier,
            descriptor: descriptor,
            displayName: "Receipt Repository",
            snapshot: RepositorySnapshot(
                entries: [
                    makeEntry(
                        title: "Receipt-backed upload",
                        happenedAt: snapshotDate
                    )
                ],
                updatedAt: snapshotDate
            ),
            generation: 9,
            baseRecordChangeTag: "receipt-baseline",
            createdAt: snapshotDate
        )
        let contentDigest = record.contentDigest
        record.markUploaded(
            descriptor: savedDescriptor,
            serverModifiedAt: serverModifiedAt,
            recordChangeTag: "uploaded-record-tag",
            uploadedAt: uploadedAt
        )
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryRootURL
        )

        try outboxStore.save(record)

        let reconstructedStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryRootURL
        )
        let reloaded = try XCTUnwrap(reconstructedStore.load())
        XCTAssertEqual(
            reloaded.receipt,
            CloudUploadReceipt(
                descriptor: savedDescriptor,
                serverModifiedAt: serverModifiedAt,
                recordChangeTag: "uploaded-record-tag",
                uploadedAt: uploadedAt
            )
        )
        XCTAssertEqual(reloaded.generation, 9)
        XCTAssertEqual(reloaded.baseRecordChangeTag, "receipt-baseline")
        XCTAssertEqual(reloaded.contentDigest, contentDigest)
        XCTAssertEqual(reloaded.snapshot, record.snapshot)
    }

    @MainActor
    func testLoadIfNeededRecoversNewerOutboxWhenSnapshotAndCatalogMarkerAreStale() async throws {
        let rootURL = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: rootURL)
        let localStore = libraryStore.repositoryStore(
            for: RepositoryReference.localRepositoryID
        )
        let descriptor = RepositoryDescriptor(
            zoneName: "restart-recovery-zone",
            zoneOwnerName: "_restart_recovery_owner_",
            shareRecordName: "restart-recovery-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let staleDate = fixtureDate("2026-07-25T12:00:00Z")
        let outboxDate = fixtureDate("2026-07-25T12:30:00Z")
        let uploadedAt = fixtureDate("2026-07-25T12:31:00Z")
        let entryID = UUID()
        let imageReference = "\(entryID.uuidString).jpg"
        let embeddedImageData = Data([
            0x74, 0x68, 0x61, 0x74, 0x44, 0x61, 0x79, 0x2d,
            0x6f, 0x75, 0x74, 0x62, 0x6f, 0x78
        ])
        let staleSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "Stale repository.json content",
                    body: "This simulates the pre-crash local snapshot.",
                    happenedAt: staleDate,
                    createdAt: staleDate,
                    updatedAt: staleDate
                )
            ],
            updatedAt: staleDate
        )
        let outboxSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "Recovered newer outbox content",
                    body: "This snapshot must win after reconstruction.",
                    happenedAt: staleDate,
                    createdAt: staleDate,
                    updatedAt: outboxDate,
                    imageReference: imageReference
                )
            ],
            updatedAt: outboxDate,
            embeddedImages: [
                RepositoryImageAsset(
                    reference: imageReference,
                    data: embeddedImageData
                )
            ],
            blogTags: ["Recovery"],
            sharedUpdateNotificationScope: .all
        )
        let referenceWithoutPendingMarker = RepositoryReference(
            id: repositoryID,
            displayName: "Restart Recovery Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: staleDate,
            lastKnownServerRecordChangeTag: "pre-crash-baseline"
        )

        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(entries: [], updatedAt: staleDate)
        )
        try repositoryStore.saveDescriptor(descriptor)
        try repositoryStore.saveSnapshot(staleSnapshot)
        try libraryStore.saveCatalog([
            RepositoryReference.local,
            referenceWithoutPendingMarker
        ])
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryStore.rootURL
        )
        let outbox = try CloudUploadOutboxRecord(
            repositoryID: repositoryID,
            descriptor: descriptor,
            displayName: referenceWithoutPendingMarker.displayName,
            snapshot: outboxSnapshot,
            generation: 12,
            baseRecordChangeTag: "pre-crash-baseline",
            createdAt: outboxDate
        )
        try outboxStore.save(outbox)

        let catalogBeforeRestart = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertNil(catalogBeforeRestart.pendingCloudUploadAt)
        XCTAssertNil(catalogBeforeRestart.pendingCloudUploadGeneration)
        XCTAssertEqual(
            try repositoryStore.loadSnapshot()?.entries.first?.title,
            "Stale repository.json content"
        )

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = outboxSnapshot
        cloudService.metadataRecordChangeTag = "uploaded-record-tag"
        cloudService.metadataServerModifiedAt = uploadedAt
        let reconstructedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { uploadedAt }
        )

        await reconstructedStore.loadIfNeeded()

        XCTAssertEqual(cloudService.savedSnapshots, [outbox.snapshot])
        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["pre-crash-baseline"]
        )
        XCTAssertEqual(
            reconstructedStore.entries.first?.title,
            "Recovered newer outbox content"
        )
        XCTAssertEqual(
            try repositoryStore.loadSnapshot(),
            outbox.snapshot.removingEmbeddedImages()
        )
        let materializedImageURL = try XCTUnwrap(
            repositoryStore.imageURL(for: imageReference)
        )
        XCTAssertEqual(
            try Data(contentsOf: materializedImageURL),
            embeddedImageData
        )
        let catalogAfterRecovery = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertNil(catalogAfterRecovery.pendingCloudUploadAt)
        XCTAssertNil(catalogAfterRecovery.pendingCloudUploadGeneration)
        XCTAssertNil(catalogAfterRecovery.pendingCloudUploadBaseChangeTag)
        XCTAssertEqual(
            catalogAfterRecovery.lastKnownServerRecordChangeTag,
            "uploaded-record-tag"
        )
        XCTAssertNil(try outboxStore.load())
    }

    func testVersionThreeBaselineSnapshotPersistsAndRejectsTampering() throws {
        let repositoryRootURL = makeTempDirectory()
            .appendingPathComponent(
                "baseline-integrity",
                isDirectory: true
            )
        let store = CloudUploadOutboxStore(
            repositoryRootURL: repositoryRootURL
        )
        let snapshotDate =
            fixtureDate("2026-07-27T06:00:00Z")
        let baseEntry = makeEntry(
            title: "Server baseline",
            happenedAt: snapshotDate
        )
        var localEntry = baseEntry
        localEntry.body = "Pending local edit"
        let record = try CloudUploadOutboxRecord(
            repositoryID: "baseline-integrity",
            descriptor: RepositoryDescriptor(
                zoneName: "baseline-integrity-zone",
                zoneOwnerName: "_baseline_integrity_owner_",
                role: .editor
            ),
            displayName: "Baseline Integrity",
            snapshot: RepositorySnapshot(
                entries: [localEntry],
                updatedAt: snapshotDate
            ),
            generation: 3,
            baseRecordChangeTag: "baseline-tag",
            baseSnapshot: RepositorySnapshot(
                entries: [baseEntry],
                updatedAt: snapshotDate
            ),
            createdAt: snapshotDate
        )
        try store.save(record)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(
            loaded.version,
            CloudUploadOutboxRecord.currentVersion
        )
        XCTAssertEqual(loaded.baseSnapshot?.entries, [baseEntry])
        XCTAssertEqual(loaded.baseContentDigest?.count, 64)

        var tampered = loaded
        tampered.baseSnapshot?.entries[0].body =
            "Tampered without updating baseline digest"
        try store.save(tampered)
        XCTAssertThrowsError(try store.load())
    }

    func testVersionThreeDigestDetectsSubsecondTimestampTampering() throws {
        let store = CloudUploadOutboxStore(
            repositoryRootURL: makeTempDirectory()
                .appendingPathComponent(
                    "subsecond-integrity",
                    isDirectory: true
                )
        )
        let snapshotDate = Date(
            timeIntervalSinceReferenceDate: 804_751_200.125
        )
        let record = try CloudUploadOutboxRecord(
            repositoryID: "subsecond-integrity",
            descriptor: RepositoryDescriptor(
                zoneName: "subsecond-integrity-zone",
                zoneOwnerName: "_subsecond_integrity_owner_",
                role: .editor
            ),
            displayName: "Subsecond Integrity",
            snapshot: RepositorySnapshot(
                entries: [
                    makeEntry(
                        title: "Precise timestamp",
                        happenedAt: snapshotDate
                    )
                ],
                updatedAt: snapshotDate
            ),
            generation: 1,
            baseRecordChangeTag: "subsecond-tag",
            createdAt: snapshotDate
        )
        try store.save(record)

        var tampered = try XCTUnwrap(store.load())
        tampered.snapshot.entries[0].updatedAt =
            snapshotDate.addingTimeInterval(0.1)
        try store.save(tampered)

        XCTAssertThrowsError(try store.load())
    }

    func testVersionTwoOutboxWithoutBaselineStillLoadsForMigration() throws {
        let repositoryRootURL = makeTempDirectory()
            .appendingPathComponent(
                "version-two-migration",
                isDirectory: true
            )
        let store = CloudUploadOutboxStore(
            repositoryRootURL: repositoryRootURL
        )
        let snapshotDate =
            fixtureDate("2026-07-27T06:10:00Z")
        let normalizedRecord = try CloudUploadOutboxRecord(
            repositoryID: "version-two-migration",
            descriptor: RepositoryDescriptor(
                zoneName: "version-two-migration-zone",
                zoneOwnerName: "_version_two_owner_",
                role: .editor
            ),
            displayName: "Version Two Migration",
            snapshot: RepositorySnapshot(
                entries: [
                    makeEntry(
                        title: "Legacy pending upload",
                        happenedAt: snapshotDate
                    )
                ],
                updatedAt: snapshotDate
            ),
            generation: 2,
            baseRecordChangeTag: nil,
            createdAt: snapshotDate
        )
        let digestEncoder = JSONEncoder()
        digestEncoder.dateEncodingStrategy = .iso8601
        digestEncoder.outputFormatting = [.sortedKeys]
        let legacyDigest = SHA256.hash(
            data: try digestEncoder.encode(
                normalizedRecord.snapshot
            )
        )
        .map { String(format: "%02x", $0) }
        .joined()
        let legacyRecord = LegacyVersionTwoOutbox(
            repositoryID: normalizedRecord.repositoryID,
            descriptor: normalizedRecord.descriptor,
            displayName: normalizedRecord.displayName,
            snapshot: normalizedRecord.snapshot,
            generation: normalizedRecord.generation,
            baseRecordChangeTag:
                normalizedRecord.baseRecordChangeTag,
            operationID: normalizedRecord.operationID,
            predecessorOperationIDs:
                normalizedRecord.predecessorOperationIDs,
            mode: normalizedRecord.mode,
            contentDigest: legacyDigest,
            createdAt: normalizedRecord.createdAt,
            receipt: normalizedRecord.receipt,
            encryptedResetAcknowledgement:
                normalizedRecord
                    .encryptedResetAcknowledgement
        )
        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .iso8601
        legacyEncoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]
        try FileManager.default.createDirectory(
            at: repositoryRootURL,
            withIntermediateDirectories: true
        )
        try legacyEncoder.encode(legacyRecord).write(
            to: store.fileURL,
            options: .atomic
        )

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.version, 2)
        XCTAssertNil(loaded.baseSnapshot)
        XCTAssertNil(loaded.baseContentDigest)
    }
}

private struct LegacyVersionTwoOutbox: Encodable {
    let version = 2
    var repositoryID: String
    var descriptor: RepositoryDescriptor
    var displayName: String
    var snapshot: RepositorySnapshot
    var generation: Int
    var baseRecordChangeTag: String?
    var operationID: UUID
    var predecessorOperationIDs: [UUID]
    var mode: CloudUploadMode
    var contentDigest: String
    var createdAt: Date
    var receipt: CloudUploadReceipt?
    var encryptedResetAcknowledgement:
        EncryptedResetAcknowledgement?
}
