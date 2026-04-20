import XCTest
@testable import thatDay

final class StorageTests: AppStoreTestCase {
    func testLoadPreferencesDefaultsNotificationScopeForLegacyPreferencesFile() throws {
        let rootURL = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: rootURL)
        let legacyPreferencesData = Data(
            """
            {
              "defaultRepositoryID" : "\(RepositoryReference.localRepositoryID)",
              "isBiometricLockEnabled" : false,
              "isSharedUpdateNotificationEnabled" : true
            }
            """.utf8
        )

        try FileManager.default.createDirectory(at: libraryStore.rootURL, withIntermediateDirectories: true)
        try legacyPreferencesData.write(to: libraryStore.preferencesURL, options: .atomic)

        let preferences = try libraryStore.loadPreferences()

        XCTAssertEqual(preferences.defaultRepositoryID, RepositoryReference.localRepositoryID)
        XCTAssertTrue(preferences.isSharedUpdateNotificationEnabled)
        XCTAssertEqual(preferences.sharedUpdateNotificationScope, .all)
    }

    func testLoadSnapshotDefaultsRepositoryNotificationScopeForLegacySnapshotFile() throws {
        let rootURL = makeTempDirectory()
        let store = LocalRepositoryStore(rootURL: rootURL)
        let happenedAt = fixtureDate("2026-04-16T09:00:00Z")
        let legacySnapshotData = Data(
            """
            {
              "blogTags" : [
                "Reading",
                "Watching",
                "Game",
                "Trip",
                "note"
              ],
              "entries" : [
                {
                  "blogImageLayout" : "landscape",
                  "body" : "Body",
                  "createdAt" : "2026-04-16T09:00:00Z",
                  "happenedAt" : "2026-04-16T09:00:00Z",
                  "id" : "11111111-1111-1111-1111-111111111111",
                  "kind" : "journal",
                  "title" : "Legacy Entry",
                  "updatedAt" : "2026-04-16T09:00:00Z"
                }
              ],
              "updatedAt" : "\(ISO8601DateFormatter().string(from: happenedAt))",
              "version" : 2
            }
            """.utf8
        )

        try FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
        try legacySnapshotData.write(to: store.archiveURL, options: .atomic)

        let snapshot = try XCTUnwrap(store.loadSnapshot())

        XCTAssertEqual(snapshot.sharedUpdateNotificationScope, .all)
        XCTAssertEqual(snapshot.entries.first?.title, "Legacy Entry")
    }

    func testStoreImageCompressesImportedPhotoBelow100KB() throws {
        let rootURL = makeTempDirectory()
        let store = LocalRepositoryStore(rootURL: rootURL)
        let originalData = try XCTUnwrap(makeLargeImageData())

        XCTAssertGreaterThan(originalData.count, EntryImageCompressor.maximumByteCount)

        let reference = try store.storeImage(data: originalData, suggestedID: UUID())
        let savedURL = try XCTUnwrap(store.imageURL(for: reference))
        let savedData = try Data(contentsOf: savedURL)

        XCTAssertLessThanOrEqual(savedData.count, EntryImageCompressor.maximumByteCount)
        XCTAssertEqual(savedURL.pathExtension.lowercased(), "jpg")
    }

    func testImageURLNormalizesLegacyLocalReferencesAndSkipsMissingFiles() throws {
        let rootURL = makeTempDirectory()
        let store = LocalRepositoryStore(rootURL: rootURL)
        let imageData = try XCTUnwrap(makePreviewImageData())
        let reference = try store.storeImage(data: imageData, suggestedID: UUID())
        let fileURLReference = store.imagesURL.appendingPathComponent(reference).absoluteString
        let absolutePathReference = store.imagesURL.appendingPathComponent(reference).path

        XCTAssertEqual(store.imageURL(for: reference)?.lastPathComponent, reference)
        XCTAssertEqual(store.imageURL(for: fileURLReference)?.lastPathComponent, reference)
        XCTAssertEqual(store.imageURL(for: absolutePathReference)?.lastPathComponent, reference)
        XCTAssertNil(store.imageURL(for: "missing.jpg"))
        XCTAssertNil(store.imageURL(for: store.imagesURL.appendingPathComponent("missing.jpg").absoluteString))
    }

    @MainActor
    func testRemovingImageFromEntryClearsReferenceAndDeletesStoredFile() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let happenedAt = fixtureDate("2026-04-16T09:00:00Z")
        let entryID = UUID()
        let imageReference = try localStore.storeImage(
            data: try XCTUnwrap(makePreviewImageData()),
            suggestedID: entryID
        )
        let entry = EntryRecord(
            id: entryID,
            kind: .journal,
            title: "With Image",
            body: "Body",
            happenedAt: happenedAt,
            createdAt: happenedAt,
            updatedAt: happenedAt,
            imageReference: imageReference
        )

        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(RepositorySnapshot(entries: [entry], updatedAt: happenedAt))

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { happenedAt }
        )
        await store.loadIfNeeded()

        let initialEntry = try XCTUnwrap(store.entries.first)
        let initialImageURL = try XCTUnwrap(store.imageURL(for: initialEntry))
        XCTAssertTrue(FileManager.default.fileExists(atPath: initialImageURL.path))

        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: initialEntry.title,
                body: initialEntry.body,
                happenedAt: initialEntry.happenedAt
            ),
            importedImageData: nil,
            removeExistingImage: true,
            editing: initialEntry
        )

        XCTAssertTrue(didSave)

        let updatedEntry = try XCTUnwrap(store.entries.first)
        XCTAssertNil(updatedEntry.imageReference)
        XCTAssertNil(store.imageURL(for: updatedEntry))
        XCTAssertFalse(FileManager.default.fileExists(atPath: initialImageURL.path))
    }

    func testRepositoryLocalImageLoadsFileURLAndSkipsRemoteURL() throws {
        let rootURL = makeTempDirectory()
        let fileURL = rootURL.appendingPathComponent("preview.png")
        try XCTUnwrap(makePreviewImageData()).write(to: fileURL, options: .atomic)

        XCTAssertNotNil(fileURL.repositoryLocalImage)
        XCTAssertNil(URL(string: "https://example.com/cover.jpg")?.repositoryLocalImage)
    }

    @MainActor
    func testDeletingEntryPersistsRemoval() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")
        let deletedEntry = makeEntry(title: "Delete Me", happenedAt: now)
        let keptEntry = makeEntry(title: "Keep Me", happenedAt: now)

        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [deletedEntry, keptEntry],
                updatedAt: now
            )
        )

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await store.loadIfNeeded()

        await store.deleteEntry(deletedEntry)

        XCTAssertNil(store.entry(matching: deletedEntry.id))
        XCTAssertEqual(store.entries.map(\.title), ["Keep Me"])

        let reloadedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await reloadedStore.loadIfNeeded()

        XCTAssertEqual(reloadedStore.entries.map(\.title), ["Keep Me"])
    }

    @MainActor
    func testClearingCurrentRepositoryPersistsEmptySnapshot() async throws {
        let storageRoot = makeTempDirectory()
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [makeEntry(title: "To Delete", happenedAt: fixtureDate("2026-04-16T09:00:00Z"))],
            rootURL: storageRoot
        )

        await store.loadIfNeeded()
        await store.clearCurrentRepository()

        XCTAssertTrue(store.entries.isEmpty)

        let reloadedStore = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            rootURL: storageRoot
        )
        await reloadedStore.loadIfNeeded()

        XCTAssertTrue(reloadedStore.entries.isEmpty)
    }
}
