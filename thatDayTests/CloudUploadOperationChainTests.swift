import Foundation
import XCTest
@testable import thatDay

final class CloudUploadOperationChainTests: AppStoreTestCase {
    func testOutboxEmbedsEnvelopeOperationIDAndNormalizesPredecessors() throws {
        let operationID = UUID()
        let predecessorA = UUID()
        let predecessorB = UUID()
        let snapshotDate = fixtureDate("2026-07-25T14:00:00Z")
        let snapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Operation-tagged upload",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate,
            cloudUploadOperationID: UUID()
        )

        let outbox = try CloudUploadOutboxRecord(
            repositoryID: "operation-tagged-repository",
            descriptor: RepositoryDescriptor(
                zoneName: "operation-tagged-zone",
                zoneOwnerName: "_operation_tagged_owner_",
                role: .editor
            ),
            displayName: "Operation Tagged Repository",
            snapshot: snapshot,
            generation: 3,
            baseRecordChangeTag: "operation-baseline",
            operationID: operationID,
            predecessorOperationIDs: [
                predecessorB,
                operationID,
                predecessorA,
                predecessorB
            ],
            createdAt: snapshotDate
        )

        XCTAssertEqual(outbox.operationID, operationID)
        XCTAssertEqual(outbox.snapshot.cloudUploadOperationID, operationID)
        XCTAssertEqual(
            Set(outbox.predecessorOperationIDs),
            Set([predecessorA, predecessorB])
        )
        XCTAssertEqual(outbox.predecessorOperationIDs.count, 2)
        XCTAssertFalse(outbox.predecessorOperationIDs.contains(operationID))
        XCTAssertNoThrow(try outbox.validatingContent())
    }

    func testNewGenerationCarriesEveryUnacknowledgedOperationAsPredecessor() throws {
        let snapshotDate = fixtureDate("2026-07-25T15:00:00Z")
        let oldestOperationID = UUID()
        let descriptor = RepositoryDescriptor(
            zoneName: "operation-chain-zone",
            zoneOwnerName: "_operation_chain_owner_",
            role: .editor
        )
        let firstOutbox = try CloudUploadOutboxRecord(
            repositoryID: descriptor.storageIdentifier,
            descriptor: descriptor,
            displayName: "Operation Chain Repository",
            snapshot: RepositorySnapshot(
                entries: [
                    makeEntry(
                        title: "First generation",
                        happenedAt: snapshotDate
                    )
                ],
                updatedAt: snapshotDate
            ),
            generation: 7,
            baseRecordChangeTag: "operation-chain-baseline",
            predecessorOperationIDs: [oldestOperationID],
            createdAt: snapshotDate
        )
        let secondOutbox = try CloudUploadOutboxRecord(
            repositoryID: descriptor.storageIdentifier,
            descriptor: descriptor,
            displayName: "Operation Chain Repository",
            snapshot: RepositorySnapshot(
                entries: [
                    makeEntry(
                        title: "Second generation",
                        happenedAt: snapshotDate
                    )
                ],
                updatedAt: snapshotDate.addingTimeInterval(60)
            ),
            generation: 8,
            baseRecordChangeTag: firstOutbox.baseRecordChangeTag,
            predecessorOperationIDs: [
                firstOutbox.operationID
            ] + firstOutbox.predecessorOperationIDs,
            createdAt: snapshotDate.addingTimeInterval(60)
        )

        XCTAssertNotEqual(secondOutbox.operationID, firstOutbox.operationID)
        XCTAssertEqual(
            Set(secondOutbox.predecessorOperationIDs),
            Set([firstOutbox.operationID, oldestOperationID])
        )
        XCTAssertEqual(
            secondOutbox.snapshot.cloudUploadOperationID,
            secondOutbox.operationID
        )
    }

    func testAdvancingBaselineClearsAcknowledgedPredecessors() throws {
        let snapshotDate = fixtureDate("2026-07-25T16:00:00Z")
        var outbox = try CloudUploadOutboxRecord(
            repositoryID: "advanced-operation-chain",
            descriptor: RepositoryDescriptor(
                zoneName: "advanced-operation-chain-zone",
                zoneOwnerName: "_advanced_operation_chain_owner_",
                role: .editor
            ),
            displayName: "Advanced Operation Chain",
            snapshot: RepositorySnapshot(
                entries: [],
                updatedAt: snapshotDate
            ),
            generation: 11,
            baseRecordChangeTag: "old-baseline",
            predecessorOperationIDs: [UUID(), UUID()],
            createdAt: snapshotDate
        )
        let operationID = outbox.operationID
        let snapshotOperationID = outbox.snapshot.cloudUploadOperationID

        try outbox.advanceBaseRecordChangeTag(
            "server-acknowledged-baseline"
        )

        XCTAssertEqual(
            outbox.baseRecordChangeTag,
            "server-acknowledged-baseline"
        )
        XCTAssertTrue(outbox.predecessorOperationIDs.isEmpty)
        XCTAssertEqual(outbox.operationID, operationID)
        XCTAssertEqual(
            outbox.snapshot.cloudUploadOperationID,
            snapshotOperationID
        )
        XCTAssertNoThrow(try outbox.validatingContent())
    }

    func testOperationChainSurvivesStoreReconstruction() throws {
        let repositoryRootURL = makeTempDirectory()
            .appendingPathComponent("operation-chain-restart", isDirectory: true)
        let store = CloudUploadOutboxStore(
            repositoryRootURL: repositoryRootURL
        )
        let snapshotDate = fixtureDate("2026-07-25T17:00:00Z")
        let operationID = UUID()
        let predecessors = [UUID(), UUID()]
        let outbox = try CloudUploadOutboxRecord(
            repositoryID: "operation-chain-restart",
            descriptor: RepositoryDescriptor(
                zoneName: "operation-chain-restart-zone",
                zoneOwnerName: "_operation_chain_restart_owner_",
                role: .editor
            ),
            displayName: "Operation Chain Restart",
            snapshot: RepositorySnapshot(
                entries: [
                    makeEntry(
                        title: "Persisted operation chain",
                        happenedAt: snapshotDate
                    )
                ],
                updatedAt: snapshotDate
            ),
            generation: 19,
            baseRecordChangeTag: "persisted-baseline",
            operationID: operationID,
            predecessorOperationIDs: predecessors,
            createdAt: snapshotDate
        )

        try store.save(outbox)

        let reconstructedStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryRootURL
        )
        let reloaded = try XCTUnwrap(reconstructedStore.load())
        XCTAssertEqual(reloaded, outbox)
        XCTAssertEqual(reloaded.operationID, operationID)
        XCTAssertEqual(
            reloaded.snapshot.cloudUploadOperationID,
            operationID
        )
        XCTAssertEqual(
            Set(reloaded.predecessorOperationIDs),
            Set(predecessors)
        )
    }

    @MainActor
    func testRestartedUploadPassesPersistedPredecessorsToCloudService() async throws {
        let rootURL = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: rootURL)
        let localStore = libraryStore.repositoryStore(
            for: RepositoryReference.localRepositoryID
        )
        let descriptor = RepositoryDescriptor(
            zoneName: "persisted-predecessor-zone",
            zoneOwnerName: "_persisted_predecessor_owner_",
            shareRecordName: "persisted-predecessor-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let baselineDate = fixtureDate("2026-07-25T18:00:00Z")
        let uploadDate = fixtureDate("2026-07-25T18:10:00Z")
        let baselineSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Baseline content",
                    happenedAt: baselineDate
                )
            ],
            updatedAt: baselineDate
        )
        let uploadSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Content after an uncertain upload",
                    happenedAt: uploadDate
                )
            ],
            updatedAt: uploadDate
        )
        let predecessorIDs = Set([UUID(), UUID()])
        let pendingReference = RepositoryReference(
            id: repositoryID,
            displayName: "Persisted Predecessor Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: baselineDate,
            lastKnownServerRecordChangeTag: "stale-baseline",
            pendingCloudUploadAt: uploadDate,
            pendingCloudUploadGeneration: 4,
            pendingCloudUploadBaseChangeTag: "stale-baseline"
        )

        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(entries: [], updatedAt: baselineDate)
        )
        try repositoryStore.saveDescriptor(descriptor)
        try repositoryStore.saveSnapshot(baselineSnapshot)
        try libraryStore.saveCatalog([
            RepositoryReference.local,
            pendingReference
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
            displayName: pendingReference.displayName,
            snapshot: uploadSnapshot,
            generation: 4,
            baseRecordChangeTag: "stale-baseline",
            predecessorOperationIDs: Array(predecessorIDs),
            createdAt: uploadDate
        )
        try outboxStore.save(outbox)

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = outbox.snapshot
        cloudService.metadataRecordChangeTag = "new-server-baseline"
        cloudService.metadataServerModifiedAt =
            uploadDate.addingTimeInterval(5)
        let reconstructedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { uploadDate.addingTimeInterval(10) }
        )

        await reconstructedStore.loadIfNeeded()

        XCTAssertEqual(cloudService.savedSnapshots, [outbox.snapshot])
        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["stale-baseline"]
        )
        XCTAssertEqual(
            cloudService.savedAcceptedPredecessorOperationIDs,
            [predecessorIDs]
        )
        XCTAssertNil(try outboxStore.load())
    }
}
