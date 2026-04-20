import XCTest
@testable import thatDay

final class RoutingTests: AppStoreTestCase {
    @MainActor
    func testRouteToJournalEntrySelectsDateAndConsumesOnJournalTab() async throws {
        let journalEntry = makeEntry(
            title: "Journal Route",
            happenedAt: fixtureDate("2025-04-17T09:00:00Z")
        )
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [journalEntry]
        )

        await store.loadIfNeeded()
        store.routeToEntry(journalEntry)

        XCTAssertEqual(store.selectedTab, .journal)
        XCTAssertEqual(Calendar.current.dayIdentifier(for: store.selectedDate), "2025-04-17")
        XCTAssertEqual(store.entryOpenRequest?.entryID, journalEntry.id)

        let destination = try XCTUnwrap(store.consumeEntryOpenRequest(for: .journal))
        XCTAssertEqual(destination, .read(journalEntry.id))
        XCTAssertNil(store.entryOpenRequest)
    }

    @MainActor
    func testConsumeEntryOpenRequestRequiresMatchingTabAndKeepsPendingRequest() async throws {
        let blogEntry = makeEntry(
            kind: .blog,
            title: "Blog Route",
            body: "Body",
            blogTag: "Trip",
            happenedAt: fixtureDate("2026-04-16T09:00:00Z")
        )
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [blogEntry]
        )

        await store.loadIfNeeded()
        store.routeToEntry(blogEntry)

        XCTAssertNil(store.consumeEntryOpenRequest(for: .journal))
        XCTAssertEqual(store.entryOpenRequest?.entryID, blogEntry.id)

        let destination = try XCTUnwrap(store.consumeEntryOpenRequest(for: .blog))
        XCTAssertEqual(destination, .read(blogEntry.id))
        XCTAssertNil(store.entryOpenRequest)
    }

    @MainActor
    func testHandleNotificationRouteSwitchesRepositoryAndRoutesToSharedEntry() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let sharedDescriptor = RepositoryDescriptor(
            zoneName: "shared-zone",
            zoneOwnerName: "_owner_",
            shareRecordName: "shared-record",
            role: .viewer
        )
        let sharedEntry = EntryRecord(
            kind: .blog,
            title: "Shared Route",
            body: "Open from notification.",
            blogTag: "Trip",
            happenedAt: fixtureDate("2026-04-16T09:00:00Z")
        )
        let sharedSnapshot = RepositorySnapshot(
            entries: [sharedEntry],
            updatedAt: fixtureDate("2026-04-16T09:00:00Z")
        )

        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [makeEntry(title: "Local Entry", happenedAt: fixtureDate("2026-04-15T09:00:00Z"))],
                updatedAt: fixtureDate("2026-04-15T09:00:00Z")
            )
        )

        let sharedStore = libraryStore.repositoryStore(for: sharedDescriptor.storageIdentifier)
        try sharedStore.saveDescriptor(sharedDescriptor)
        try sharedStore.saveSnapshot(sharedSnapshot)
        try libraryStore.saveCatalog([
            RepositoryReference.local,
            RepositoryReference(
                id: sharedDescriptor.storageIdentifier,
                displayName: "Shared Repository",
                descriptor: sharedDescriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: sharedSnapshot.updatedAt
            )
        ])

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = sharedSnapshot
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await store.loadIfNeeded()

        await store.handleNotificationRoute(
            NotificationEntryRoute(
                repositoryID: sharedDescriptor.storageIdentifier,
                entryID: sharedEntry.id
            )
        )

        XCTAssertEqual(store.currentRepositoryID, sharedDescriptor.storageIdentifier)
        XCTAssertEqual(store.selectedTab, .blog)
        XCTAssertEqual(store.entryOpenRequest?.repositoryID, sharedDescriptor.storageIdentifier)
        XCTAssertEqual(store.entryOpenRequest?.entryID, sharedEntry.id)
        XCTAssertTrue(cloudService.loadedDescriptors.contains(sharedDescriptor))

        let destination = try XCTUnwrap(store.consumeEntryOpenRequest(for: .blog))
        XCTAssertEqual(destination, .read(sharedEntry.id))
    }
}
