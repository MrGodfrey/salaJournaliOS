import XCTest
@testable import thatDay

final class ArchiveTests: AppStoreTestCase {
    func testRepositoryArchiveRoundTripRestoresSnapshot() async throws {
        let rootURL = makeTempDirectory()
        let sourceStore = LocalRepositoryStore(rootURL: rootURL.appendingPathComponent("source", isDirectory: true))
        let destinationStore = LocalRepositoryStore(rootURL: rootURL.appendingPathComponent("destination", isDirectory: true))
        let snapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    kind: .journal,
                    title: "Export Me",
                    body: "Archive body",
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ],
            updatedAt: fixtureDate("2026-04-16T09:00:00Z")
        )

        try sourceStore.saveDescriptor(.local)
        try sourceStore.saveSnapshot(snapshot)
        _ = try sourceStore.storeImage(data: try XCTUnwrap(makePreviewImageData()), suggestedID: snapshot.entries[0].id)

        let service = RepositoryArchiveService()
        let zipURL = try await service.exportArchive(
            from: sourceStore,
            repositoryID: RepositoryReference.localRepositoryID,
            repositoryName: "My Repo"
        ) { _, _ in }

        let importedSnapshot = try await service.importArchive(
            from: zipURL,
            into: destinationStore,
            preserving: .local
        ) { _, _ in }

        XCTAssertEqual(importedSnapshot.entries.map(\.title), ["Export Me"])
        XCTAssertNotNil(try destinationStore.exportableFileURLs().first(where: { $0.lastPathComponent.hasSuffix(".jpg") }))
    }

    func testRepositoryArchiveRoundTripRestoresImagesForTmpSymlinkPaths() async throws {
        let rootURL = try makeSymlinkedTempDirectory()
        XCTAssertNotEqual(rootURL.path, rootURL.resolvingSymlinksInPath().path)

        let sourceStore = LocalRepositoryStore(rootURL: rootURL.appendingPathComponent("source", isDirectory: true))
        let destinationStore = LocalRepositoryStore(rootURL: rootURL.appendingPathComponent("destination", isDirectory: true))
        let imageData = try XCTUnwrap(makePreviewImageData())
        let entryID = UUID()
        let imageReference = try sourceStore.storeImage(data: imageData, suggestedID: entryID)
        let snapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "Tmp Path Image",
                    body: "Archive body",
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z"),
                    createdAt: fixtureDate("2026-04-16T09:00:00Z"),
                    updatedAt: fixtureDate("2026-04-16T09:00:00Z"),
                    imageReference: imageReference
                )
            ],
            updatedAt: fixtureDate("2026-04-16T09:00:00Z")
        )

        try sourceStore.saveDescriptor(.local)
        try sourceStore.saveSnapshot(snapshot)

        let zipURL = try await RepositoryArchiveService().exportArchive(
            from: sourceStore,
            repositoryID: RepositoryReference.localRepositoryID,
            repositoryName: "Tmp Repo"
        ) { _, _ in }

        let importedSnapshot = try await RepositoryArchiveService().importArchive(
            from: zipURL,
            into: destinationStore,
            preserving: .local
        ) { _, _ in }

        let importedEntry = try XCTUnwrap(importedSnapshot.entries.first)
        let importedImageURL = try XCTUnwrap(destinationStore.imageURL(for: importedEntry.imageReference))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedImageURL.path))
        XCTAssertNotNil(importedImageURL.repositoryLocalImage)
    }

    @MainActor
    func testExportCurrentRepositoryCreatesArchiveItemThatCanBeImported() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let repositoryStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")
        let entry = makeEntry(title: "Exported by AppStore", happenedAt: now)

        try repositoryStore.saveDescriptor(.local)
        try repositoryStore.saveSnapshot(RepositorySnapshot(entries: [entry], updatedAt: now))

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await store.loadIfNeeded()

        await store.exportCurrentRepository()

        XCTAssertNil(store.transferProgress)
        let exportedItem = try XCTUnwrap(store.exportedArchiveItem)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedItem.url.path))
        XCTAssertEqual(exportedItem.url.pathExtension.lowercased(), "zip")

        let importedStore = LocalRepositoryStore(rootURL: makeTempDirectory().appendingPathComponent("imported", isDirectory: true))
        let importedSnapshot = try await RepositoryArchiveService().importArchive(
            from: exportedItem.url,
            into: importedStore,
            preserving: .local
        ) { _, _ in }

        XCTAssertEqual(importedSnapshot.entries.map(\.title), ["Exported by AppStore"])
    }

    @MainActor
    func testExportThenImportIntoSameRepositoryKeepsLoadableImage() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let repositoryStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let cloudService = MockCloudRepositoryService()
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        let imageData = try XCTUnwrap(makePreviewImageData())

        try repositoryStore.saveDescriptor(.local)
        let imageReference = try repositoryStore.storeImage(data: imageData, suggestedID: UUID())
        try repositoryStore.saveSnapshot(
            RepositorySnapshot(
                entries: [
                    EntryRecord(
                        kind: .blog,
                        title: "Self Import",
                        body: "Round trip",
                        happenedAt: fixtureDate("2026-04-16T09:00:00Z"),
                        createdAt: fixtureDate("2026-04-16T09:00:00Z"),
                        updatedAt: fixtureDate("2026-04-16T09:00:00Z"),
                        imageReference: imageReference
                    )
                ],
                updatedAt: fixtureDate("2026-04-16T09:00:00Z")
            )
        )

        await store.loadIfNeeded()
        let exportedURL = try await RepositoryArchiveService().exportArchive(
            from: repositoryStore,
            repositoryID: RepositoryReference.localRepositoryID,
            repositoryName: "Self Import"
        ) { _, _ in }

        await store.importRepositoryArchive(from: exportedURL)

        let importedEntry = try XCTUnwrap(store.entries.first)
        let importedImageURL = try XCTUnwrap(store.imageURL(for: importedEntry))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedImageURL.path))
        XCTAssertNotNil(importedImageURL.repositoryLocalImage)
        XCTAssertGreaterThan(try Data(contentsOf: importedImageURL).count, 0)
    }

    func testImportArchiveStartsAndStopsSecurityScopedAccess() async throws {
        let rootURL = makeTempDirectory()
        let sourceStore = LocalRepositoryStore(rootURL: rootURL.appendingPathComponent("source", isDirectory: true))
        let destinationStore = LocalRepositoryStore(rootURL: rootURL.appendingPathComponent("destination", isDirectory: true))
        let selectedArchiveURL = rootURL.appendingPathComponent("picked.zip")
        let snapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    kind: .journal,
                    title: "Security Scoped Import",
                    body: "Archive body",
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ],
            updatedAt: fixtureDate("2026-04-16T09:00:00Z")
        )

        try sourceStore.saveDescriptor(.local)
        try sourceStore.saveSnapshot(snapshot)

        var didStartAccessing = false
        var didStopAccessing = false
        let service = RepositoryArchiveService(
            extractArchive: { _, unzipRoot in
                XCTAssertTrue(didStartAccessing)
                XCTAssertFalse(didStopAccessing)

                let extractedRepositoryURL = unzipRoot.appendingPathComponent("repository", isDirectory: true)
                try FileManager.default.createDirectory(at: extractedRepositoryURL, withIntermediateDirectories: true)

                for fileURL in try sourceStore.exportableFileURLs() {
                    let destinationURL = extractedRepositoryURL.appendingPathComponent(fileURL.lastPathComponent)
                    try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                }
            },
            startAccessingSecurityScopedResource: { url in
                XCTAssertEqual(url, selectedArchiveURL)
                didStartAccessing = true
                return true
            },
            stopAccessingSecurityScopedResource: { url in
                XCTAssertEqual(url, selectedArchiveURL)
                didStopAccessing = true
            }
        )

        let importedSnapshot = try await service.importArchive(
            from: selectedArchiveURL,
            into: destinationStore,
            preserving: .local
        ) { _, _ in }

        XCTAssertEqual(importedSnapshot.entries.map(\.title), ["Security Scoped Import"])
        XCTAssertTrue(didStartAccessing)
        XCTAssertTrue(didStopAccessing)
    }

    func testImportArchiveMapsNoPermissionToUserFacingError() async throws {
        let rootURL = makeTempDirectory()
        let destinationStore = LocalRepositoryStore(rootURL: rootURL.appendingPathComponent("destination", isDirectory: true))
        let service = RepositoryArchiveService(
            extractArchive: { _, _ in
                throw CocoaError(.fileReadNoPermission)
            }
        )

        do {
            _ = try await service.importArchive(
                from: rootURL.appendingPathComponent("picked.zip"),
                into: destinationStore,
                preserving: .local
            ) { _, _ in }
            XCTFail("Expected importArchive to throw")
        } catch let error as RepositoryArchiveError {
            XCTAssertEqual(error.errorDescription, "The selected ZIP file could not be read. Choose it again and retry.")
        }
    }
}
