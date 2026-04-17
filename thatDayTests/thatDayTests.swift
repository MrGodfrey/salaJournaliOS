import CloudKit
import SwiftUI
import UIKit
import XCTest
@testable import thatDay

final class thatDayTests: XCTestCase {
    @MainActor
    func testJournalSectionsGroupEntriesByMonthDayAcrossYears() async throws {
        let entries = [
            makeEntry(title: "2026", happenedAt: fixtureDate("2026-04-16T09:00:00Z")),
            makeEntry(title: "2025", happenedAt: fixtureDate("2025-04-16T08:00:00Z")),
            makeEntry(title: "2024", happenedAt: fixtureDate("2024-04-16T07:00:00Z")),
            makeEntry(title: "2023", happenedAt: fixtureDate("2023-04-16T06:00:00Z")),
            makeEntry(title: "Ignore me", happenedAt: fixtureDate("2026-04-18T06:00:00Z"))
        ]
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: entries
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.journalSections.map(\.year), [2026, 2025, 2024, 2023])
        XCTAssertEqual(store.journalSections.first?.entries.first?.title, "2026")
    }

    @MainActor
    func testEmptySearchDoesNotShowAnyResults() async throws {
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [makeEntry(title: "Welcome", happenedAt: fixtureDate("2026-04-16T09:00:00Z"))]
        )

        await store.loadIfNeeded()

        XCTAssertTrue(store.searchResults.isEmpty)
    }

    @MainActor
    func testSearchMatchesJournalAndBlogContent() async throws {
        let entries = [
            makeEntry(title: "Morning Journal", happenedAt: fixtureDate("2026-04-16T09:00:00Z")),
            makeEntry(
                kind: .blog,
                title: "The Art of Morning Stillness",
                body: "A quiet morning changes the whole day.",
                happenedAt: fixtureDate("2026-04-15T09:00:00Z")
            )
        ]
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: entries
        )

        await store.loadIfNeeded()
        store.searchText = "morning"

        let titles = store.searchResults.map(\.title)
        XCTAssertTrue(titles.contains("Morning Journal"))
        XCTAssertTrue(titles.contains("The Art of Morning Stillness"))
    }

    @MainActor
    func testMovingSelectedDateAndReturningToToday() async throws {
        let store = try makeStore(now: fixtureDate("2026-04-16T09:00:00Z"))
        await store.loadIfNeeded()

        store.moveSelectedDate(by: 1)
        XCTAssertEqual(Calendar.current.dayIdentifier(for: store.selectedDate), "2026-04-17")

        store.returnToToday()
        XCTAssertEqual(Calendar.current.dayIdentifier(for: store.selectedDate), "2026-04-16")
    }

    @MainActor
    func testSettingDisplayedMonthUpdatesMonthAndYear() async throws {
        let store = try makeStore(now: fixtureDate("2026-04-16T09:00:00Z"))
        await store.loadIfNeeded()

        store.setDisplayedMonth(year: 2024, month: 2)

        XCTAssertEqual(Calendar.current.component(.year, from: store.displayedMonth), 2024)
        XCTAssertEqual(Calendar.current.component(.month, from: store.displayedMonth), 2)
        XCTAssertEqual(Calendar.current.component(.day, from: store.displayedMonth), 1)
    }

    func testCalendarGridBuildsCompleteWeeksAndSelection() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let displayedMonth = fixtureDate("2026-04-01T00:00:00Z")
        let selectedDate = fixtureDate("2026-04-17T00:00:00Z")
        let days = CalendarGridBuilder.makeMonthGrid(
            displayedMonth: displayedMonth,
            selectedDate: selectedDate,
            journalDates: [selectedDate],
            calendar: calendar
        )

        XCTAssertEqual(days.count, 35)
        XCTAssertEqual(days.first?.key, "2026-03-29")
        XCTAssertEqual(days.last?.key, "2026-05-02")
        XCTAssertEqual(days.first(where: \.isSelected)?.key, "2026-04-17")
        XCTAssertEqual(days.first(where: { $0.key == "2026-04-17" })?.hasJournalEntries, true)
    }

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
    func testBlogEntriesDefaultToNoteTagAndWrittenStatisticsCountAllEntries() async throws {
        let entries = [
            makeEntry(
                title: "Morning Note",
                body: "Three calm lines",
                happenedAt: fixtureDate("2026-04-16T09:00:00Z")
            ),
            makeEntry(
                kind: .blog,
                title: "Reading Log",
                body: "Four quick test words",
                happenedAt: fixtureDate("2026-04-15T09:00:00Z")
            )
        ]
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: entries
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.blogEntries.first?.blogTag, "note")
        XCTAssertEqual(store.journalEntryCount, 1)
        XCTAssertEqual(store.blogEntryCount, 1)
        XCTAssertEqual(store.writtenWordCount, 11)
    }

    @MainActor
    func testWrittenWordCountUsesKAbbreviationAfterOneThousandWords() async throws {
        let largeBody = Array(repeating: "word", count: 1_098).joined(separator: " ")
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [
                makeEntry(
                    title: "Big Count",
                    body: largeBody,
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ]
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.writtenWordCount, 1_100)
        XCTAssertEqual(store.formattedWrittenWordCount, "1.1K")
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
    func testOpeningBlogTagSwitchesToBlogTabAndAppliesFilter() async throws {
        let store = try makeStore(now: fixtureDate("2026-04-16T09:00:00Z"))
        await store.loadIfNeeded()

        store.openBlog(tag: "Trip")

        XCTAssertEqual(store.selectedTab, .blog)
        XCTAssertEqual(store.selectedBlogTag, "Trip")
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

    func testRepositoryLocalImageLoadsFileURLAndSkipsRemoteURL() throws {
        let rootURL = makeTempDirectory()
        let fileURL = rootURL.appendingPathComponent("preview.png")
        try XCTUnwrap(makePreviewImageData()).write(to: fileURL, options: .atomic)

        XCTAssertNotNil(fileURL.repositoryLocalImage)
        XCTAssertNil(URL(string: "https://example.com/cover.jpg")?.repositoryLocalImage)
    }

    @MainActor
    func testUserFacingMessageMapsCloudKitProductionSchemaError() {
        let error = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.serverRejectedRequest.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Error saving record <CKRecordID: 0x1; recordName=RepositoryRoot, zonelD=thatday-repository:_defaultOwner_> to server: Cannot create new type RepositoryRoot in production schema"
            ]
        )

        XCTAssertEqual(
            AppStore.userFacingMessage(for: error),
            "The CloudKit production environment has not deployed the RepositoryRoot record type yet. Deploy the development schema to production in CloudKit Console, then create the share link again."
        )
    }

    @MainActor
    func testUserFacingMessageMapsNestedCloudKitProductionSchemaError() {
        let itemError = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.serverRejectedRequest.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Error saving record <CKRecordID: 0x1; recordName=RepositoryRoot, zonelD=thatday-repository:_defaultOwner_> to server: Cannot create new type RepositoryRoot in production schema"
            ]
        )
        let zoneID = CKRecordZone.ID(zoneName: "thatday-repository", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: "RepositoryRoot", zoneID: zoneID)
        let error = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [
                CKPartialErrorsByItemIDKey: [recordID: itemError]
            ]
        )

        XCTAssertEqual(
            AppStore.userFacingMessage(for: error),
            "The CloudKit production environment has not deployed the RepositoryRoot record type yet. Deploy the development schema to production in CloudKit Console, then create the share link again."
        )
    }

    @MainActor
    func testBiometricLockAuthenticatesOnLaunchAndOnlyReauthenticatesAfterBackground() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [makeEntry(title: "Protected Entry", happenedAt: now)],
                updatedAt: now
            )
        )
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: true,
                isSharedUpdateNotificationEnabled: false
            )
        )

        let biometricAuthenticator = MockBiometricAuthenticator()
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now },
            authenticateBiometrics: biometricAuthenticator.authenticate
        )

        await store.loadIfNeeded()
        XCTAssertEqual(biometricAuthenticator.reasons, ["Unlock thatDay"])
        XCTAssertFalse(store.isAuthenticationRequired)

        await store.handleScenePhaseChange(.active)
        XCTAssertEqual(biometricAuthenticator.reasons.count, 1)
        XCTAssertFalse(store.isAuthenticationRequired)

        await store.handleScenePhaseChange(.background)
        XCTAssertTrue(store.isAuthenticationRequired)

        await store.handleScenePhaseChange(.active)
        XCTAssertEqual(biometricAuthenticator.reasons, ["Unlock thatDay", "Unlock thatDay"])
        XCTAssertFalse(store.isAuthenticationRequired)
    }

    @MainActor
    func testAcceptingShareKeepsLocalRepositoryAndAddsSharedRepository() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let localEntry = makeEntry(title: "Local Journal", happenedAt: fixtureDate("2026-04-16T09:00:00Z"))
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(RepositorySnapshot(entries: [localEntry], updatedAt: fixtureDate("2026-04-16T09:00:00Z")))

        let cloudService = MockCloudRepositoryService()
        let sharedSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    kind: .journal,
                    title: "Shared Journal",
                    body: "Read only entry.",
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ],
            updatedAt: fixtureDate("2026-04-16T09:00:00Z")
        )
        cloudService.acceptedSharedRepository = AcceptedSharedRepository(
            descriptor: RepositoryDescriptor(
                zoneName: "shared-zone",
                zoneOwnerName: "_owner_",
                shareRecordName: "shared-record",
                role: .viewer
            ),
            snapshot: sharedSnapshot,
            displayName: "Shared Repository"
        )
        cloudService.loadedSnapshot = sharedSnapshot

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await store.loadIfNeeded()

        store.incomingShareLink = "https://www.icloud.com/share/mock-share"
        await store.acceptIncomingShareLink()

        XCTAssertEqual(store.repositoryDescriptor.role, .viewer)
        XCTAssertFalse(store.canEditRepository)
        XCTAssertEqual(store.entries.first?.title, "Shared Journal")
        XCTAssertEqual(store.sortedRepositories.count, 2)

        await store.switchRepository(to: RepositoryReference.localRepositoryID)
        XCTAssertEqual(store.repositoryDescriptor.role, .local)
        XCTAssertEqual(store.entries.first?.title, "Local Journal")
    }

    @MainActor
    func testDefaultRepositoryLoadsChosenSharedRepositoryOnLaunch() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let sharedDescriptor = RepositoryDescriptor(
            zoneName: "shared-zone",
            zoneOwnerName: "_owner_",
            shareRecordName: "shared-record",
            role: .viewer
        )
        let sharedSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    kind: .blog,
                    title: "Shared Blog",
                    body: "Cloud entry.",
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ],
            updatedAt: fixtureDate("2026-04-16T09:00:00Z")
        )

        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(RepositorySnapshot(
            entries: [makeEntry(title: "Local Entry", happenedAt: fixtureDate("2026-04-15T09:00:00Z"))],
            updatedAt: fixtureDate("2026-04-15T09:00:00Z")
        ))

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
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: sharedDescriptor.storageIdentifier,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = sharedSnapshot

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await store.loadIfNeeded()

        XCTAssertEqual(store.currentRepositoryID, sharedDescriptor.storageIdentifier)
        XCTAssertEqual(store.entries.first?.title, "Shared Blog")
        XCTAssertEqual(store.repositoryDescriptor.role, .viewer)
    }

    @MainActor
    func testSavingSharedRepositoryUploadsEmbeddedImagesToCloud() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let sharedDescriptor = RepositoryDescriptor(
            zoneName: "owner-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "owner-share",
            role: .owner
        )
        let repositoryID = sharedDescriptor.storageIdentifier
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let happenedAt = fixtureDate("2026-04-16T09:00:00Z")
        let entryID = UUID()
        let imageReference = try repositoryStore.storeImage(
            data: try XCTUnwrap(makePreviewImageData()),
            suggestedID: entryID
        )
        let entry = EntryRecord(
            id: entryID,
            kind: .blog,
            title: "Shared Blog",
            body: "Has image",
            happenedAt: happenedAt,
            createdAt: happenedAt,
            updatedAt: happenedAt,
            imageReference: imageReference
        )
        let snapshot = RepositorySnapshot(entries: [entry], updatedAt: happenedAt)

        try repositoryStore.saveDescriptor(sharedDescriptor)
        try repositoryStore.saveSnapshot(snapshot)
        try libraryStore.saveCatalog([
            RepositoryReference.local,
            RepositoryReference(
                id: repositoryID,
                displayName: "Shared Repository",
                descriptor: sharedDescriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: snapshot.updatedAt
            )
        ])
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = snapshot

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T10:00:00Z") }
        )
        await store.loadIfNeeded()

        let existingEntry = try XCTUnwrap(store.entries.first)
        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .blog,
                title: "Shared Blog Updated",
                body: "Has image",
                happenedAt: happenedAt
            ),
            importedImageData: nil,
            editing: existingEntry
        )

        XCTAssertTrue(didSave)
        let uploadedSnapshot = try XCTUnwrap(cloudService.savedSnapshots.last)
        XCTAssertEqual(uploadedSnapshot.entries.first?.imageReference, imageReference)
        XCTAssertEqual(uploadedSnapshot.embeddedImages.map(\.reference), [imageReference])
        XCTAssertFalse(uploadedSnapshot.embeddedImages.isEmpty)
    }

    @MainActor
    func testManualRefreshUpdatesSharedRepositoryAndMaterializesImages() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let sharedDescriptor = RepositoryDescriptor(
            zoneName: "shared-zone",
            zoneOwnerName: "_owner_",
            shareRecordName: "shared-record",
            role: .viewer
        )
        let repositoryID = sharedDescriptor.storageIdentifier
        let sharedStore = libraryStore.repositoryStore(for: repositoryID)
        let initialDate = fixtureDate("2026-04-16T09:00:00Z")
        let refreshedDate = fixtureDate("2026-04-16T11:00:00Z")
        let refreshedImageData = try XCTUnwrap(makePreviewImageData())
        let refreshedEntryID = UUID()
        let initialSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: refreshedEntryID,
                    kind: .blog,
                    title: "Shared Blog",
                    body: "Old content",
                    happenedAt: initialDate,
                    createdAt: initialDate,
                    updatedAt: initialDate
                )
            ],
            updatedAt: initialDate
        )
        let refreshedSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: refreshedEntryID,
                    kind: .blog,
                    title: "Shared Blog Updated",
                    body: "New content",
                    happenedAt: initialDate,
                    createdAt: initialDate,
                    updatedAt: refreshedDate,
                    imageReference: "\(refreshedEntryID.uuidString).jpg"
                )
            ],
            updatedAt: refreshedDate,
            embeddedImages: [
                RepositoryImageAsset(
                    reference: "\(refreshedEntryID.uuidString).jpg",
                    data: refreshedImageData
                )
            ]
        )

        try sharedStore.saveDescriptor(sharedDescriptor)
        try sharedStore.saveSnapshot(initialSnapshot)
        try libraryStore.saveCatalog([
            RepositoryReference.local,
            RepositoryReference(
                id: repositoryID,
                displayName: "Shared Repository",
                descriptor: sharedDescriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: initialSnapshot.updatedAt
            )
        ])
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T12:00:00Z") }
        )
        await store.loadIfNeeded()

        XCTAssertEqual(store.entries.first?.title, "Shared Blog")

        cloudService.loadedSnapshot = refreshedSnapshot
        await store.refreshSharedRepositories(trigger: .manual)

        let refreshedEntry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(refreshedEntry.title, "Shared Blog Updated")

        let imageURL = try XCTUnwrap(store.imageURL(for: refreshedEntry))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertEqual(try Data(contentsOf: imageURL), refreshedImageData)

        let cachedSnapshot = try XCTUnwrap(sharedStore.loadSnapshot())
        XCTAssertTrue(cachedSnapshot.embeddedImages.isEmpty)
        XCTAssertEqual(cachedSnapshot.entries.first?.title, "Shared Blog Updated")
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
        try sourceStore.storeImage(data: try XCTUnwrap(makePreviewImageData()), suggestedID: snapshot.entries[0].id)

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
        let rootURL = URL(fileURLWithPath: "/tmp/thatDay-archive-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: rootURL)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

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

    @MainActor
    func testSharedRepositoryPushRefreshSetsBadgeAndActiveClearsIt() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let sharedDescriptor = RepositoryDescriptor(
            zoneName: "shared-zone",
            zoneOwnerName: "_owner_",
            shareRecordName: "shared-record",
            role: .viewer
        )
        let repositoryID = sharedDescriptor.storageIdentifier
        let sharedStore = libraryStore.repositoryStore(for: repositoryID)
        let initialDate = fixtureDate("2026-04-16T09:00:00Z")
        let updatedDate = fixtureDate("2026-04-16T11:00:00Z")
        let entryID = UUID()
        let initialSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "Shared Blog",
                    body: "Old content",
                    happenedAt: initialDate,
                    createdAt: initialDate,
                    updatedAt: initialDate
                )
            ],
            updatedAt: initialDate
        )
        let updatedSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "Shared Blog Updated",
                    body: "New content",
                    happenedAt: initialDate,
                    createdAt: initialDate,
                    updatedAt: updatedDate
                )
            ],
            updatedAt: updatedDate
        )

        try sharedStore.saveDescriptor(sharedDescriptor)
        try sharedStore.saveSnapshot(initialSnapshot)
        try libraryStore.saveCatalog([
            RepositoryReference.local,
            RepositoryReference(
                id: repositoryID,
                displayName: "Shared Repository",
                descriptor: sharedDescriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: initialSnapshot.updatedAt
            )
        ])
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: true
            )
        )

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        var badgeCounts: [Int] = []
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T12:00:00Z") },
            setApplicationBadgeCount: { badgeCounts.append($0) }
        )

        await store.loadIfNeeded()
        XCTAssertEqual(badgeCounts.last, 0)

        await store.handleScenePhaseChange(.background)
        cloudService.loadedSnapshot = updatedSnapshot
        await store.refreshSharedRepositories(trigger: .push)

        XCTAssertEqual(badgeCounts.last, 1)

        await store.handleScenePhaseChange(.active)
        XCTAssertEqual(badgeCounts.last, 0)
    }

    @MainActor
    func testForegroundRefreshDoesNotRestoreBadgeAfterAppOpens() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let sharedDescriptor = RepositoryDescriptor(
            zoneName: "shared-zone",
            zoneOwnerName: "_owner_",
            shareRecordName: "shared-record",
            role: .viewer
        )
        let repositoryID = sharedDescriptor.storageIdentifier
        let sharedStore = libraryStore.repositoryStore(for: repositoryID)
        let initialDate = fixtureDate("2026-04-16T09:00:00Z")
        let updatedDate = fixtureDate("2026-04-16T11:00:00Z")
        let entryID = UUID()
        let initialSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "Shared Blog",
                    body: "Old content",
                    happenedAt: initialDate,
                    createdAt: initialDate,
                    updatedAt: initialDate
                )
            ],
            updatedAt: initialDate
        )
        let updatedSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "Shared Blog Updated",
                    body: "New content",
                    happenedAt: initialDate,
                    createdAt: initialDate,
                    updatedAt: updatedDate
                )
            ],
            updatedAt: updatedDate
        )

        try sharedStore.saveDescriptor(sharedDescriptor)
        try sharedStore.saveSnapshot(initialSnapshot)
        try libraryStore.saveCatalog([
            RepositoryReference.local,
            RepositoryReference(
                id: repositoryID,
                displayName: "Shared Repository",
                descriptor: sharedDescriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: initialSnapshot.updatedAt
            )
        ])
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: true
            )
        )

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        var badgeCounts: [Int] = []
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T12:00:00Z") },
            setApplicationBadgeCount: { badgeCounts.append($0) }
        )

        await store.loadIfNeeded()
        await store.handleScenePhaseChange(.active)

        cloudService.loadedSnapshot = updatedSnapshot
        await store.refreshSharedRepositories(trigger: .foreground)

        XCTAssertEqual(badgeCounts.last, 0)
        XCTAssertFalse(badgeCounts.contains(1))
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

    @MainActor
    private func makeStore(now: Date, entries: [EntryRecord]? = nil, rootURL: URL? = nil) throws -> AppStore {
        let libraryRoot = rootURL ?? makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: libraryRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        try localStore.saveDescriptor(.local)
        if let entries {
            try localStore.saveSnapshot(RepositorySnapshot(entries: entries, updatedAt: now))
        }

        return AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
    }

    private func makeEntry(
        kind: EntryKind = .journal,
        title: String,
        body: String = "Body",
        blogTag: String? = nil,
        happenedAt: Date
    ) -> EntryRecord {
        EntryRecord(
            kind: kind,
            title: title,
            body: body,
            blogTag: blogTag,
            happenedAt: happenedAt,
            createdAt: happenedAt,
            updatedAt: happenedAt
        )
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePreviewImageData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200))
        let image = renderer.image { context in
            context.cgContext.setFillColor(UIColor.systemIndigo.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(x: 24, y: 24, width: 272, height: 152))
        }
        return image.pngData()
    }

    private func makeLargeImageData() -> Data? {
        let side = 2200
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            for row in stride(from: 0, to: side, by: 40) {
                for column in stride(from: 0, to: side, by: 40) {
                    let red = CGFloat((row / 40) % 11) / 10
                    let green = CGFloat((column / 40) % 13) / 12
                    let blue = CGFloat(((row + column) / 40) % 17) / 16
                    context.cgContext.setFillColor(UIColor(red: red, green: green, blue: blue, alpha: 1).cgColor)
                    context.cgContext.fill(CGRect(x: column, y: row, width: 40, height: 40))
                }
            }
        }
        return image.pngData()
    }

    private func fixtureDate(_ rawValue: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue) ?? .now
    }
}

private final class MockCloudRepositoryService: CloudRepositoryServicing {
    var loadedSnapshot: RepositorySnapshot?
    var acceptedSharedRepository: AcceptedSharedRepository?
    var savedSnapshots: [RepositorySnapshot] = []

    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot {
        if let loadedSnapshot {
            return loadedSnapshot
        }

        throw CloudRepositoryError.repositoryNotFound
    }

    func saveSnapshot(_ snapshot: RepositorySnapshot, using descriptor: RepositoryDescriptor) async throws -> RepositoryDescriptor {
        savedSnapshots.append(snapshot)

        if descriptor.role == .local {
            return RepositoryDescriptor(
                zoneName: "mock-zone",
                zoneOwnerName: CKCurrentUserDefaultName,
                shareRecordName: "mock-share",
                role: .owner
            )
        }

        return descriptor
    }

    func shareURL(using descriptor: RepositoryDescriptor, snapshot: RepositorySnapshot) async throws -> URL {
        URL(string: "https://www.icloud.com/share/mock-share")!
    }

    func ensureRepositorySubscription(using descriptor: RepositoryDescriptor) async throws {}

    @MainActor
    func makeSharingController(
        using descriptor: RepositoryDescriptor,
        snapshot: RepositorySnapshot,
        access: ShareAccessOption
    ) async throws -> UICloudSharingController {
        UICloudSharingController(
            share: CKShare(recordZoneID: CKRecordZone.ID(zoneName: "mock-zone", ownerName: CKCurrentUserDefaultName)),
            container: CKContainer(identifier: "iCloud.yu.thatDay")
        )
    }

    func acceptShare(from url: URL) async throws -> AcceptedSharedRepository {
        if let acceptedSharedRepository {
            return acceptedSharedRepository
        }

        throw CloudRepositoryError.shareLinkInvalid
    }

    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository {
        try await acceptShare(from: URL(string: "https://www.icloud.com/share/mock-share")!)
    }
}

private final class MockBiometricAuthenticator {
    private(set) var reasons: [String] = []

    func authenticate(reason: String) async throws {
        reasons.append(reason)
    }
}
