import XCTest
@testable import thatDay

final class CloudChangeTokenStoreTests: AppStoreTestCase {
    func testPendingModifiedAndDeletedZonesPersistAndAcknowledgeIndependently() throws {
        let directoryURL = makeTempDirectory()
            .appendingPathComponent("cloudkit-change-tokens", isDirectory: true)
        let firstStore = CloudChangeTokenStore(directoryURL: directoryURL)
        let modifiedZoneA = CloudRepositoryZoneIdentity(
            ownerName: "_owner_a_",
            zoneName: "modified-a"
        )
        let modifiedZoneB = CloudRepositoryZoneIdentity(
            ownerName: "_owner_b_",
            zoneName: "modified-b"
        )
        let deletedZone = CloudRepositoryZoneDeletion(
            zoneID: CloudRepositoryZoneIdentity(
                ownerName: "_owner_c_",
                zoneName: "deleted-c"
            ),
            reason: .purged
        )

        try firstStore.savePendingZoneIDs(
            [modifiedZoneA, modifiedZoneB],
            for: .sharedDatabase
        )
        try firstStore.savePendingDeletedZones(
            [deletedZone],
            for: .sharedDatabase
        )

        let reconstructedStore = CloudChangeTokenStore(directoryURL: directoryURL)
        XCTAssertEqual(
            try reconstructedStore.loadPendingZoneIDs(for: .sharedDatabase),
            [modifiedZoneA, modifiedZoneB]
        )
        XCTAssertEqual(
            try reconstructedStore.loadPendingDeletedZones(for: .sharedDatabase),
            [deletedZone]
        )

        try reconstructedStore.acknowledgePendingZoneIDs(
            [modifiedZoneA],
            for: .sharedDatabase
        )
        XCTAssertEqual(
            try reconstructedStore.loadPendingZoneIDs(for: .sharedDatabase),
            [modifiedZoneB]
        )
        XCTAssertEqual(
            try reconstructedStore.loadPendingDeletedZones(for: .sharedDatabase),
            [deletedZone]
        )

        try reconstructedStore.acknowledgePendingDeletedZones(
            [deletedZone],
            for: .sharedDatabase
        )
        XCTAssertEqual(
            try reconstructedStore.loadPendingDeletedZones(for: .sharedDatabase),
            []
        )
    }

    func testResetRemovesPendingInboxForBothDatabaseScopes() throws {
        let directoryURL = makeTempDirectory()
            .appendingPathComponent("cloudkit-change-tokens", isDirectory: true)
        let store = CloudChangeTokenStore(directoryURL: directoryURL)
        let zone = CloudRepositoryZoneIdentity(
            ownerName: "_owner_",
            zoneName: "pending-zone"
        )
        let deletion = CloudRepositoryZoneDeletion(
            zoneID: zone,
            reason: .encryptedDataReset
        )

        try store.savePendingZoneIDs([zone], for: .privateDatabase)
        try store.savePendingZoneIDs([zone], for: .sharedDatabase)
        try store.savePendingDeletedZones([deletion], for: .privateDatabase)
        try store.savePendingDeletedZones([deletion], for: .sharedDatabase)

        try store.removeAllTrackingState()

        XCTAssertEqual(try store.loadPendingZoneIDs(for: .privateDatabase), [])
        XCTAssertEqual(try store.loadPendingZoneIDs(for: .sharedDatabase), [])
        XCTAssertEqual(
            try store.loadPendingDeletedZones(for: .privateDatabase),
            []
        )
        XCTAssertEqual(
            try store.loadPendingDeletedZones(for: .sharedDatabase),
            []
        )
    }
}
