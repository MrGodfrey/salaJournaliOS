import CoreGraphics
import XCTest
@testable import thatDay

final class BlogTagTests: AppStoreTestCase {
    @MainActor
    func testSavingBlogEntryPersistsToLocalStore() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let cloudService = MockCloudRepositoryService()
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )

        await store.loadIfNeeded()
        store.showEditor(for: .blog)
        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .blog,
                title: "A New Persisted Blog",
                body: "Saved from unit tests.",
                happenedAt: fixtureDate("2026-04-16T09:00:00Z")
            ),
            importedImageData: nil
        )

        XCTAssertTrue(didSave)

        let reloadedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await reloadedStore.loadIfNeeded()

        XCTAssertTrue(reloadedStore.blogEntries.contains(where: { $0.title == "A New Persisted Blog" }))
        XCTAssertEqual(reloadedStore.currentRepositoryID, RepositoryReference.localRepositoryID)
    }

    @MainActor
    func testSavingBlogEntryPersistsSelectedImageLayout() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let cloudService = MockCloudRepositoryService()
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )

        await store.loadIfNeeded()

        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .blog,
                title: "Portrait Blog",
                body: "Saved with portrait layout.",
                blogImageLayout: .portrait,
                happenedAt: fixtureDate("2026-04-16T09:00:00Z")
            ),
            importedImageData: nil
        )

        XCTAssertTrue(didSave)

        let reloadedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await reloadedStore.loadIfNeeded()

        XCTAssertEqual(reloadedStore.blogEntries.first?.blogImageLayout, .portrait)
    }

    func testLoadingLegacyBlogEntryDefaultsImageLayoutToLandscape() throws {
        let snapshotData = Data(
            """
            {
              "entries" : [
                {
                  "id" : "E0D5F1A0-1C1F-4B01-9464-6E4E4A7A9D11",
                  "kind" : "blog",
                  "title" : "Legacy Blog",
                  "body" : "Saved before image layouts existed.",
                  "blogTag" : "Reading",
                  "happenedAt" : "2026-04-16T09:00:00Z",
                  "createdAt" : "2026-04-16T09:00:00Z",
                  "updatedAt" : "2026-04-16T09:00:00Z"
                }
              ],
              "updatedAt" : "2026-04-16T09:00:00Z"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(RepositorySnapshot.self, from: snapshotData)

        XCTAssertEqual(snapshot.entries.first?.blogImageLayout, .landscape)
    }

    @MainActor
    func testAddingBlogTagTrimsPersistsAndRejectsDiacriticInsensitiveDuplicate() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")

        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [],
                updatedAt: now,
                blogTags: ["Reading", "Trip", "note"]
            )
        )

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await store.loadIfNeeded()

        await store.addBlogTag(named: "  Café  ")

        XCTAssertEqual(store.blogTags, ["Reading", "Trip", "note", "Café"])

        let reloadedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await reloadedStore.loadIfNeeded()
        XCTAssertEqual(reloadedStore.blogTags, ["Reading", "Trip", "note", "Café"])

        await store.addBlogTag(named: "cafe")

        XCTAssertEqual(store.alertMessage, "That blog tag already exists.")
        XCTAssertEqual(store.blogTags, ["Reading", "Trip", "note", "Café"])
    }

    @MainActor
    func testDeletingBlogTagReassignsEntriesAndPersists() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")

        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [
                    makeEntry(
                        kind: .blog,
                        title: "Reading Post",
                        body: "Tagged reading",
                        blogTag: "Reading",
                        happenedAt: now
                    ),
                    makeEntry(
                        kind: .blog,
                        title: "Trip Post",
                        body: "Tagged trip",
                        blogTag: "Trip",
                        happenedAt: now
                    )
                ],
                updatedAt: now,
                blogTags: ["Reading", "Trip", "note"]
            )
        )

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await store.loadIfNeeded()

        await store.deleteBlogTag("Reading", reassigningEntriesTo: "Trip")

        XCTAssertEqual(store.blogTags, ["Trip", "note"])
        XCTAssertEqual(store.blogEntries.compactMap(\.blogTag), ["Trip", "Trip"])

        let reloadedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await reloadedStore.loadIfNeeded()

        XCTAssertEqual(reloadedStore.blogTags, ["Trip", "note"])
        XCTAssertEqual(reloadedStore.blogEntries.compactMap(\.blogTag), ["Trip", "Trip"])
    }

    @MainActor
    func testMovingBlogTagsFromOffsetsPersists() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")

        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [],
                updatedAt: now,
                blogTags: ["Reading", "Watching", "Trip", "note"]
            )
        )

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await store.loadIfNeeded()

        await store.moveBlogTags(fromOffsets: IndexSet(integer: 3), toOffset: 0)

        XCTAssertEqual(store.blogTags, ["note", "Reading", "Watching", "Trip"])

        let reloadedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await reloadedStore.loadIfNeeded()

        XCTAssertEqual(reloadedStore.blogTags, ["note", "Reading", "Watching", "Trip"])
    }

    @MainActor
    func testMovingBlogTagRelativeToAnotherTagPersists() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")

        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [
                    makeEntry(
                        kind: .blog,
                        title: "Reading Post",
                        body: "Tagged reading",
                        blogTag: "Reading",
                        happenedAt: now
                    ),
                    makeEntry(
                        kind: .blog,
                        title: "Trip Post",
                        body: "Tagged trip",
                        blogTag: "Trip",
                        happenedAt: now
                    )
                ],
                updatedAt: now,
                blogTags: ["Reading", "Watching", "Trip", "note"]
            )
        )

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await store.loadIfNeeded()

        await store.moveBlogTag(named: "note", relativeTo: "Reading", placingAfter: false)
        await store.moveBlogTag(named: "Reading", relativeTo: "Trip", placingAfter: true)

        XCTAssertEqual(store.blogTags, ["note", "Watching", "Trip", "Reading"])

        let reloadedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await reloadedStore.loadIfNeeded()

        XCTAssertEqual(reloadedStore.blogTags, ["note", "Watching", "Trip", "Reading"])
    }

    @MainActor
    func testOpeningBlogTagSwitchesToBlogTabAndAppliesFilter() async throws {
        let store = try makeStore(now: fixtureDate("2026-04-16T09:00:00Z"))
        await store.loadIfNeeded()

        store.openBlog(tag: "Trip")

        XCTAssertEqual(store.selectedTab, .blog)
        XCTAssertEqual(store.selectedBlogTag, "Trip")
    }

    @MainActor
    func testBlogTagHorizontalSwipeMovesAcrossFilterOptions() async throws {
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [],
            blogTags: ["Reading", "Trip", "note"]
        )
        await store.loadIfNeeded()

        let leftSwipe = try XCTUnwrap(
            HorizontalSwipeDirection.direction(for: CGSize(width: -96, height: 6))
        )
        store.moveSelectedBlogTag(by: leftSwipe.pageOffset)
        XCTAssertEqual(store.selectedBlogTag, "Reading")

        store.moveSelectedBlogTag(by: leftSwipe.pageOffset)
        XCTAssertEqual(store.selectedBlogTag, "Trip")

        let rightSwipe = try XCTUnwrap(
            HorizontalSwipeDirection.direction(for: CGSize(width: 96, height: 6))
        )
        store.moveSelectedBlogTag(by: rightSwipe.pageOffset)
        XCTAssertEqual(store.selectedBlogTag, "Reading")

        store.selectedBlogTag = "note"
        store.moveSelectedBlogTag(by: leftSwipe.pageOffset)
        XCTAssertEqual(store.selectedBlogTag, "note")
    }

    @MainActor
    func testOpenBlogNormalizesSelectedTagForFilteringAcrossBlogEntries() async throws {
        let entries = [
            makeEntry(
                kind: .blog,
                title: "Reading Summary",
                body: "A reading note.",
                blogTag: "Reading",
                happenedAt: fixtureDate("2026-04-16T09:00:00Z")
            ),
            makeEntry(
                kind: .blog,
                title: "Trip Recap",
                body: "A trip note.",
                blogTag: "Trip",
                happenedAt: fixtureDate("2026-04-15T09:00:00Z")
            )
        ]
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: entries
        )

        await store.loadIfNeeded()
        store.openBlog(tag: "  tríp  ")

        let filteredTitles = store.blogEntries
            .filter { $0.blogTag == store.selectedBlogTag }
            .map(\.title)

        XCTAssertEqual(store.selectedBlogTag, "Trip")
        XCTAssertEqual(filteredTitles, ["Trip Recap"])
    }
}
