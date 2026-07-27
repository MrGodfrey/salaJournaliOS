import XCTest
@testable import thatDay

final class ArchiveTests: AppStoreTestCase {
    func testPreparingImportDoesNotTouchDestinationOrExistingOutbox() async throws {
        let rootURL = makeTempDirectory()
        let sourceStore = LocalRepositoryStore(
            rootURL: rootURL.appendingPathComponent("prepare-source", isDirectory: true)
        )
        let destinationStore = LocalRepositoryStore(
            rootURL: rootURL.appendingPathComponent("prepare-destination", isDirectory: true)
        )
        let initialDate = fixtureDate("2026-07-25T15:00:00Z")
        let importedDate = fixtureDate("2026-07-25T16:00:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(title: "Destination stays live", happenedAt: initialDate)
            ],
            updatedAt: initialDate
        )
        let importedSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(title: "Staged import", happenedAt: importedDate)
            ],
            updatedAt: importedDate
        )
        let descriptor = RepositoryDescriptor(
            zoneName: "prepare-import-zone",
            zoneOwnerName: "_prepare_import_owner_",
            shareRecordName: "prepare-import-share",
            role: .owner
        )
        try sourceStore.saveDescriptor(.local)
        try sourceStore.saveSnapshot(importedSnapshot)
        try destinationStore.saveDescriptor(descriptor)
        try destinationStore.saveSnapshot(initialSnapshot)
        let existingOutbox = try CloudUploadOutboxRecord(
            repositoryID: descriptor.storageIdentifier,
            descriptor: descriptor,
            displayName: "Prepare Import",
            snapshot: initialSnapshot,
            generation: 4,
            baseRecordChangeTag: "prepare-baseline",
            createdAt: initialDate
        )
        let destinationOutboxStore = CloudUploadOutboxStore(
            repositoryRootURL: destinationStore.rootURL
        )
        try destinationOutboxStore.save(existingOutbox)
        let service = RepositoryArchiveService()
        let zipURL = try await service.exportArchive(
            from: sourceStore,
            repositoryID: RepositoryReference.localRepositoryID,
            repositoryName: "Prepared Import"
        ) { _, _ in }

        let preparedImport = try await service.prepareImportArchive(
            from: zipURL,
            nextTo: destinationStore,
            preserving: descriptor
        ) { _, _ in }

        XCTAssertEqual(try destinationStore.loadSnapshot(), initialSnapshot)
        XCTAssertEqual(try destinationOutboxStore.load(), existingOutbox)
        XCTAssertEqual(preparedImport.snapshot, importedSnapshot)
        XCTAssertEqual(
            try preparedImport.repositoryStore.loadSnapshot(),
            importedSnapshot
        )

        try service.discardPreparedImport(preparedImport)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: preparedImport.repositoryStore.rootURL.path
            )
        )
    }

    func testInstallingPreparedImportKeepsSuccessorOutboxAcrossDirectoryReplacement() async throws {
        let rootURL = makeTempDirectory()
        let sourceStore = LocalRepositoryStore(
            rootURL: rootURL.appendingPathComponent("install-source", isDirectory: true)
        )
        let destinationStore = LocalRepositoryStore(
            rootURL: rootURL.appendingPathComponent("install-destination", isDirectory: true)
        )
        let initialDate = fixtureDate("2026-07-25T16:30:00Z")
        let importedDate = fixtureDate("2026-07-25T17:00:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(title: "Before safe replacement", happenedAt: initialDate)
            ],
            updatedAt: initialDate
        )
        let importedSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(title: "After safe replacement", happenedAt: importedDate)
            ],
            updatedAt: importedDate
        )
        let descriptor = RepositoryDescriptor(
            zoneName: "install-import-zone",
            zoneOwnerName: "_install_import_owner_",
            shareRecordName: "install-import-share",
            role: .owner
        )
        try sourceStore.saveDescriptor(.local)
        try sourceStore.saveSnapshot(importedSnapshot)
        try destinationStore.saveDescriptor(descriptor)
        try destinationStore.saveSnapshot(initialSnapshot)
        let service = RepositoryArchiveService()
        let zipURL = try await service.exportArchive(
            from: sourceStore,
            repositoryID: RepositoryReference.localRepositoryID,
            repositoryName: "Install Import"
        ) { _, _ in }
        let preparedImport = try await service.prepareImportArchive(
            from: zipURL,
            nextTo: destinationStore,
            preserving: descriptor
        ) { _, _ in }
        let predecessorOperationID = UUID()
        let successorOutbox = try CloudUploadOutboxRecord(
            repositoryID: descriptor.storageIdentifier,
            descriptor: descriptor,
            displayName: "Install Import",
            snapshot: importedSnapshot,
            generation: 8,
            baseRecordChangeTag: "install-baseline",
            predecessorOperationIDs: [predecessorOperationID],
            createdAt: importedDate
        )
        try CloudUploadOutboxStore(
            repositoryRootURL: destinationStore.rootURL
        ).save(successorOutbox)
        try CloudUploadOutboxStore(
            repositoryRootURL: preparedImport.repositoryStore.rootURL
        ).save(successorOutbox)

        let installedSnapshot = try service.installPreparedImport(
            preparedImport,
            replacing: destinationStore
        )

        XCTAssertEqual(installedSnapshot, importedSnapshot)
        XCTAssertEqual(try destinationStore.loadSnapshot(), importedSnapshot)
        XCTAssertEqual(
            try CloudUploadOutboxStore(
                repositoryRootURL: destinationStore.rootURL
            ).load(),
            successorOutbox
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: rootURL
                    .appendingPathComponent(
                        ".install-destination-import-transaction.json"
                    )
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: preparedImport.repositoryStore.rootURL.path
            )
        )
    }

    func testCommittedImportSurvivesCleanupFailureAndFinishesRecoveryLater() async throws {
        let rootURL = makeTempDirectory()
        let sourceStore = LocalRepositoryStore(
            rootURL: rootURL.appendingPathComponent(
                "cleanup-source",
                isDirectory: true
            )
        )
        let destinationStore = LocalRepositoryStore(
            rootURL: rootURL.appendingPathComponent(
                "cleanup-destination",
                isDirectory: true
            )
        )
        let initialDate = fixtureDate("2026-07-25T17:10:00Z")
        let importedDate = fixtureDate("2026-07-25T17:20:00Z")
        try sourceStore.saveDescriptor(.local)
        try sourceStore.saveSnapshot(
            RepositorySnapshot(
                entries: [
                    makeEntry(
                        title: "Committed despite cleanup failure",
                        happenedAt: importedDate
                    )
                ],
                updatedAt: importedDate
            )
        )
        try destinationStore.saveDescriptor(.local)
        try destinationStore.saveSnapshot(
            RepositorySnapshot(
                entries: [
                    makeEntry(
                        title: "Replaced destination",
                        happenedAt: initialDate
                    )
                ],
                updatedAt: initialDate
            )
        )

        var cleanupAttemptCount = 0
        let service = RepositoryArchiveService(
            cleanupImportTransactionArtifacts: {
                destinationURL,
                stagingURL,
                backupURL,
                keepingDestination in
                cleanupAttemptCount += 1
                if cleanupAttemptCount == 1 {
                    throw ArchiveTestError.cleanupFailed
                }

                let fileManager = FileManager.default
                for url in [stagingURL, backupURL]
                where fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                if !keepingDestination,
                   fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                let transactionURL = destinationURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        ".\(destinationURL.lastPathComponent)-import-transaction.json"
                    )
                if fileManager.fileExists(atPath: transactionURL.path) {
                    try fileManager.removeItem(at: transactionURL)
                }
            }
        )
        let zipURL = try await service.exportArchive(
            from: sourceStore,
            repositoryID: RepositoryReference.localRepositoryID,
            repositoryName: "Cleanup Failure"
        ) { _, _ in }
        let preparedImport = try await service.prepareImportArchive(
            from: zipURL,
            nextTo: destinationStore,
            preserving: .local
        ) { _, _ in }

        let installedSnapshot = try service.installPreparedImport(
            preparedImport,
            replacing: destinationStore
        )

        XCTAssertEqual(
            installedSnapshot.entries.map(\.title),
            ["Committed despite cleanup failure"]
        )
        XCTAssertEqual(
            try destinationStore.loadSnapshot()?.entries.map(\.title),
            ["Committed despite cleanup failure"]
        )
        let transactionURL = rootURL.appendingPathComponent(
            ".cleanup-destination-import-transaction.json"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: transactionURL.path)
        )

        try service.recoverInterruptedImport(for: destinationStore)

        XCTAssertEqual(cleanupAttemptCount, 2)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: transactionURL.path)
        )
        XCTAssertEqual(
            try destinationStore.loadSnapshot()?.entries.map(\.title),
            ["Committed despite cleanup failure"]
        )
    }

    @MainActor
    func testCloudImportChainsPendingOperationAndUploadsImportedSnapshot() async throws {
        let rootURL = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(
            rootURL: rootURL.appendingPathComponent("library", isDirectory: true)
        )
        let sourceStore = LocalRepositoryStore(
            rootURL: rootURL.appendingPathComponent("cloud-import-source", isDirectory: true)
        )
        let initialDate = fixtureDate("2026-07-25T17:30:00Z")
        let pendingDate = fixtureDate("2026-07-25T18:00:00Z")
        let importedDate = fixtureDate("2026-07-25T18:30:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(title: "Initial cloud cache", happenedAt: initialDate)
            ],
            updatedAt: initialDate
        )
        let pendingSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(title: "Pending before import", happenedAt: pendingDate)
            ],
            updatedAt: pendingDate
        )
        let importedSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(title: "Imported successor", happenedAt: importedDate)
            ],
            updatedAt: importedDate
        )
        let descriptor = RepositoryDescriptor(
            zoneName: "cloud-import-zone",
            zoneOwnerName: "_cloud_import_owner_",
            shareRecordName: "cloud-import-share",
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let localStore = libraryStore.repositoryStore(
            for: RepositoryReference.localRepositoryID
        )
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(RepositorySnapshot(entries: []))
        try repositoryStore.saveDescriptor(descriptor)
        try repositoryStore.saveSnapshot(initialSnapshot)
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Cloud Import",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: initialDate,
            lastKnownServerRecordChangeTag: "cloud-import-baseline",
            pendingCloudUploadAt: pendingDate,
            pendingCloudUploadGeneration: 1,
            pendingCloudUploadBaseChangeTag: "cloud-import-baseline"
        )
        try libraryStore.saveCatalog([.local, reference])
        try libraryStore.savePreferences(
            AppPreferences(defaultRepositoryID: repositoryID)
        )
        let pendingOutbox = try CloudUploadOutboxRecord(
            repositoryID: repositoryID,
            descriptor: descriptor,
            displayName: reference.displayName,
            snapshot: pendingSnapshot,
            generation: 1,
            baseRecordChangeTag: "cloud-import-baseline",
            createdAt: pendingDate
        )
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryStore.rootURL
        )
        try outboxStore.save(pendingOutbox)
        try sourceStore.saveDescriptor(.local)
        try sourceStore.saveSnapshot(importedSnapshot)
        let zipURL = try await RepositoryArchiveService().exportArchive(
            from: sourceStore,
            repositoryID: RepositoryReference.localRepositoryID,
            repositoryName: "Cloud Import Source"
        ) { _, _ in }

        let cloudService = MockCloudRepositoryService()
        cloudService.saveSnapshotError = ArchiveTestError.uploadFailed
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { importedDate.addingTimeInterval(60) }
        )
        await store.loadIfNeeded()
        XCTAssertEqual(try outboxStore.load()?.operationID, pendingOutbox.operationID)

        cloudService.savedSnapshots.removeAll()
        cloudService.savedDescriptors.removeAll()
        cloudService.savedExpectedRecordChangeTags.removeAll()
        cloudService.savedAcceptedPredecessorOperationIDs.removeAll()
        cloudService.saveSnapshotError = nil
        cloudService.savedRecordChangeTag = "cloud-import-saved-tag"
        let uploadFinished = expectation(
            description: "imported successor upload finishes"
        )
        cloudService.saveSnapshotFinishedExpectation = uploadFinished

        await store.importRepositoryArchive(from: zipURL)
        await fulfillment(of: [uploadFinished], timeout: 2)
        cloudService.saveSnapshotFinishedExpectation = nil
        for _ in 0..<100 {
            if try outboxStore.load() == nil {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(cloudService.savedSnapshots.count, 1)
        XCTAssertEqual(
            cloudService.savedSnapshots.first?.entries.map(\.title),
            ["Imported successor"]
        )
        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["cloud-import-baseline"]
        )
        XCTAssertEqual(
            cloudService.savedAcceptedPredecessorOperationIDs,
            [Set([pendingOutbox.operationID])]
        )
        XCTAssertEqual(
            try repositoryStore.loadSnapshot()?.entries.map(\.title),
            ["Imported successor"]
        )
        XCTAssertNil(try outboxStore.load())
        let completedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first { $0.id == repositoryID }
        )
        XCTAssertNil(completedReference.pendingCloudUploadGeneration)
        XCTAssertEqual(
            completedReference.lastKnownServerRecordChangeTag,
            "cloud-import-saved-tag"
        )
    }

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

    func testRepositoryArchiveRoundTripPreservesNestedReadOnlyRecoveryCopy() async throws {
        let rootURL = makeTempDirectory()
        let sourceStore = LocalRepositoryStore(
            rootURL: rootURL.appendingPathComponent(
                "recovery-source",
                isDirectory: true
            )
        )
        let destinationStore = LocalRepositoryStore(
            rootURL: rootURL.appendingPathComponent(
                "recovery-destination",
                isDirectory: true
            )
        )
        let snapshotDate = fixtureDate(
            "2026-07-25T17:30:00Z"
        )
        let viewerDescriptor = RepositoryDescriptor(
            zoneName: "recovery-archive-zone",
            zoneOwnerName: "_recovery_archive_owner_",
            shareRecordName: "recovery-archive-share",
            role: .viewer
        )
        let imageData = try XCTUnwrap(
            makePreviewImageData()
        )
        let entryID = UUID()
        let imageReference = try sourceStore.storeImage(
            data: imageData,
            suggestedID: entryID
        )
        let storedImageData = try Data(
            contentsOf: XCTUnwrap(
                sourceStore.imageURL(
                    for: imageReference
                )
            )
        )
        let snapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "Recoverable local copy",
                    body: "Must survive ZIP export and import.",
                    happenedAt: snapshotDate,
                    createdAt: snapshotDate,
                    updatedAt: snapshotDate,
                    imageReference: imageReference
                )
            ],
            updatedAt: snapshotDate
        )
        try sourceStore.saveDescriptor(viewerDescriptor)
        try sourceStore.saveSnapshot(snapshot)
        let sourceRecoveryURL =
            try sourceStore.preserveReadOnlyRecoveryCopy(
                identifier: "archive-round-trip"
            )
        XCTAssertEqual(
            try LocalRepositoryStore(
                rootURL: sourceRecoveryURL
            ).loadDescriptor(),
            viewerDescriptor
        )

        let service = RepositoryArchiveService()
        let zipURL = try await service.exportArchive(
            from: sourceStore,
            repositoryID: viewerDescriptor.storageIdentifier,
            repositoryName: "Recovery Archive"
        ) { _, _ in }
        _ = try await service.importArchive(
            from: zipURL,
            into: destinationStore,
            preserving: .local
        ) { _, _ in }

        let importedRecoveryStore =
            LocalRepositoryStore(
                rootURL: destinationStore.rootURL
                    .appendingPathComponent(
                        "read-only-upload-recovery",
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        "cached-repository-archive-round-trip",
                        isDirectory: true
                    )
            )
        XCTAssertEqual(
            try destinationStore.loadDescriptor(),
            .local
        )
        XCTAssertEqual(
            try importedRecoveryStore.loadDescriptor(),
            viewerDescriptor
        )
        XCTAssertEqual(
            try importedRecoveryStore.loadSnapshot(),
            snapshot
        )
        let recoveredImageURL = try XCTUnwrap(
            importedRecoveryStore.imageURL(
                for: imageReference
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: recoveredImageURL),
            storedImageData
        )
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

private enum ArchiveTestError: Error {
    case cleanupFailed
    case uploadFailed
}
