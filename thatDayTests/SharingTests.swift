import CloudKit
import SwiftUI
import XCTest
@testable import thatDay

final class SharingTests: AppStoreTestCase {
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
        XCTAssertEqual(cloudService.acceptedShareURLs, [URL(string: "https://www.icloud.com/share/mock-share")!])

        await store.switchRepository(to: RepositoryReference.localRepositoryID)
        XCTAssertEqual(store.repositoryDescriptor.role, .local)
        XCTAssertEqual(store.entries.first?.title, "Local Journal")
    }

    @MainActor
    func testAcceptingShareMetadataLoadsSharedRepositoryWithoutUsingURLPath() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [makeEntry(title: "Local Entry", happenedAt: fixtureDate("2026-04-16T09:00:00Z"))],
                updatedAt: fixtureDate("2026-04-16T09:00:00Z")
            )
        )

        let sharedSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    kind: .blog,
                    title: "Shared Blog",
                    body: "Loaded from metadata.",
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ],
            updatedAt: fixtureDate("2026-04-16T09:00:00Z")
        )
        let cloudService = MockCloudRepositoryService()
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

        await store.acceptShare(metadata: try makeShareMetadata())

        XCTAssertEqual(cloudService.acceptedShareMetadataCount, 1)
        XCTAssertTrue(cloudService.acceptedShareURLs.isEmpty)
        XCTAssertEqual(store.currentRepositoryName, "Shared Repository")
        XCTAssertEqual(store.repositoryDescriptor.role, .viewer)
        XCTAssertEqual(store.entries.first?.title, "Shared Blog")
        XCTAssertEqual(store.sortedRepositories.count, 2)
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
        XCTAssertTrue(cloudService.loadedDescriptors.contains(sharedDescriptor))
        XCTAssertGreaterThanOrEqual(cloudService.loadedDescriptors.count, 1)
    }

    @MainActor
    func testSetDefaultRepositoryPersistsChosenRepository() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let sharedDescriptor = RepositoryDescriptor(
            zoneName: "shared-zone",
            zoneOwnerName: "_owner_",
            shareRecordName: "shared-record",
            role: .viewer
        )
        let sharedSnapshot = RepositorySnapshot(
            entries: [],
            updatedAt: fixtureDate("2026-04-16T09:00:00Z")
        )

        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(RepositorySnapshot(entries: [], updatedAt: fixtureDate("2026-04-15T09:00:00Z")))

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

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await store.loadIfNeeded()

        store.setDefaultRepository(sharedDescriptor.storageIdentifier)

        XCTAssertEqual(store.defaultRepositoryID, sharedDescriptor.storageIdentifier)
        XCTAssertEqual(
            try libraryStore.loadPreferences().defaultRepositoryID,
            sharedDescriptor.storageIdentifier
        )
    }

    @MainActor
    func testSetSharedUpdateNotificationEnabledPersistsPreference() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await store.loadIfNeeded()

        store.setSharedUpdateNotificationEnabled(true)

        XCTAssertTrue(store.isSharedUpdateNotificationEnabled)
        XCTAssertTrue(try libraryStore.loadPreferences().isSharedUpdateNotificationEnabled)
    }

    @MainActor
    func testSetSharedUpdateNotificationScopePersistsPreference() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await store.loadIfNeeded()

        store.setSharedUpdateNotificationScope(.blog)

        XCTAssertEqual(store.sharedUpdateNotificationScope, .blog)
        XCTAssertEqual(try libraryStore.loadPreferences().sharedUpdateNotificationScope, .blog)
    }

    @MainActor
    func testUpdateRepositorySharedUpdateNotificationScopePersistsToRepositorySnapshot() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")

        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [makeEntry(title: "Local Entry", happenedAt: now)],
                updatedAt: now
            )
        )

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await store.loadIfNeeded()

        await store.updateRepositorySharedUpdateNotificationScope(.blog)

        XCTAssertEqual(store.repositorySharedUpdateNotificationScope, .blog)
        XCTAssertEqual(
            try XCTUnwrap(localStore.loadSnapshot()).sharedUpdateNotificationScope,
            .blog
        )
    }

    @MainActor
    func testNonOwnerCannotChangeRepositorySharedUpdateNotificationScope() async throws {
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
        let now = fixtureDate("2026-04-16T09:00:00Z")
        let snapshot = RepositorySnapshot(
            entries: [makeEntry(kind: .blog, title: "Shared Blog", happenedAt: now)],
            updatedAt: now,
            sharedUpdateNotificationScope: .journal
        )

        try sharedStore.saveDescriptor(sharedDescriptor)
        try sharedStore.saveSnapshot(snapshot)
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

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
        await store.loadIfNeeded()
        await store.updateRepositorySharedUpdateNotificationScope(.blog)

        XCTAssertEqual(store.repositorySharedUpdateNotificationScope, .journal)
        XCTAssertEqual(
            store.alertMessage,
            "Only the repository owner can change this repository's push update rule."
        )
    }

    @MainActor
    func testLoadIfNeededEnsuresSharedRepositorySubscriptionsWhenNotificationsEnabled() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let sharedDescriptor = RepositoryDescriptor(
            zoneName: "shared-zone",
            zoneOwnerName: "_owner_",
            shareRecordName: "shared-record",
            role: .viewer
        )
        let sharedSnapshot = RepositorySnapshot(
            entries: [],
            updatedAt: fixtureDate("2026-04-16T09:00:00Z")
        )

        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(RepositorySnapshot(entries: [], updatedAt: fixtureDate("2026-04-15T09:00:00Z")))

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
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: true
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

        XCTAssertEqual(
            cloudService.ensuredSubscriptionDescriptors.map(\.storageIdentifier),
            [sharedDescriptor.storageIdentifier]
        )
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

    @MainActor
    func testForegroundActivationRefreshesSharedRepositoriesOnlyAfterThreshold() async throws {
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
        let initialSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
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
                isSharedUpdateNotificationEnabled: false
            )
        )

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        var currentDate = fixtureDate("2026-04-16T12:00:00Z")
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { currentDate }
        )

        await store.loadIfNeeded()
        XCTAssertEqual(cloudService.loadedDescriptors.count, 1)
        XCTAssertEqual(store.entries.first?.title, "Shared Blog")

        currentDate = fixtureDate("2026-04-16T12:10:00Z")
        cloudService.loadedSnapshot = updatedSnapshot
        await store.handleScenePhaseChange(.active)

        XCTAssertEqual(cloudService.loadedDescriptors.count, 1)
        XCTAssertEqual(store.entries.first?.title, "Shared Blog")

        currentDate = fixtureDate("2026-04-16T12:31:00Z")
        await store.handleScenePhaseChange(.active)

        XCTAssertEqual(cloudService.loadedDescriptors.count, 2)
        XCTAssertEqual(store.entries.first?.title, "Shared Blog Updated")
    }

    @MainActor
    func testAutomaticForegroundRefreshFailureStaysSilentForCurrentSharedRepository() async throws {
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
        let initialSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
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
        var currentDate = fixtureDate("2026-04-16T12:00:00Z")
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { currentDate }
        )

        await store.loadIfNeeded()

        currentDate = fixtureDate("2026-04-16T12:31:00Z")
        cloudService.loadedSnapshot = nil
        await store.handleScenePhaseChange(.active)

        XCTAssertNil(store.alertMessage)
        XCTAssertEqual(store.entries.first?.title, "Shared Blog")
    }

    @MainActor
    func testManualRefreshFailureShowsAlertForCurrentSharedRepository() async throws {
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
        let initialSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
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

        cloudService.loadedSnapshot = nil
        await store.refreshSharedRepositories(trigger: .manual)

        XCTAssertEqual(
            store.alertMessage,
            CloudRepositoryError.repositoryNotFound.errorDescription
        )
    }

    @MainActor
    func testSwitchingToCachedSharedRepositoryUsesLocalSnapshotWhenSilentRefreshFails() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let sharedDescriptor = RepositoryDescriptor(
            zoneName: "shared-zone",
            zoneOwnerName: "_owner_",
            shareRecordName: "shared-record",
            role: .viewer
        )
        let repositoryID = sharedDescriptor.storageIdentifier
        let sharedStore = libraryStore.repositoryStore(for: repositoryID)
        let localDate = fixtureDate("2026-04-15T09:00:00Z")
        let sharedDate = fixtureDate("2026-04-16T09:00:00Z")

        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [makeEntry(title: "Local Entry", happenedAt: localDate)],
                updatedAt: localDate
            )
        )
        try sharedStore.saveDescriptor(sharedDescriptor)
        try sharedStore.saveSnapshot(
            RepositorySnapshot(
                entries: [
                    EntryRecord(
                        kind: .blog,
                        title: "Shared Blog",
                        body: "Cached content",
                        happenedAt: sharedDate,
                        createdAt: sharedDate,
                        updatedAt: sharedDate
                    )
                ],
                updatedAt: sharedDate
            )
        )
        try libraryStore.saveCatalog([
            RepositoryReference.local,
            RepositoryReference(
                id: repositoryID,
                displayName: "Shared Repository",
                descriptor: sharedDescriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: sharedDate
            )
        ])
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )

        let cloudService = MockCloudRepositoryService()
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T12:00:00Z") }
        )

        await store.loadIfNeeded()
        cloudService.loadedDescriptors.removeAll()

        await store.switchRepository(to: repositoryID)

        XCTAssertEqual(store.currentRepositoryID, repositoryID)
        XCTAssertEqual(store.entries.first?.title, "Shared Blog")
        XCTAssertNil(store.alertMessage)
        XCTAssertEqual(cloudService.loadedDescriptors, [sharedDescriptor])
    }

    @MainActor
    func testRefreshingSharedRepositoryDuringSaveKeepsNewJournalEntryVisibleAndPersisted() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let sharedDescriptor = RepositoryDescriptor(
            zoneName: "shared-zone",
            zoneOwnerName: "_owner_",
            shareRecordName: "shared-record",
            role: .editor
        )
        let repositoryID = sharedDescriptor.storageIdentifier
        let sharedStore = libraryStore.repositoryStore(for: repositoryID)
        let initialDate = fixtureDate("2026-04-16T09:00:00Z")
        let saveDate = fixtureDate("2026-04-16T10:00:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Earlier Shared Journal",
                    happenedAt: initialDate
                )
            ],
            updatedAt: initialDate
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
        cloudService.pauseSaveSnapshot = true
        cloudService.saveSnapshotStartedExpectation = expectation(description: "cloud save paused")

        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { saveDate }
        )
        await store.loadIfNeeded()

        let saveTask = Task {
            await store.saveEntry(
                draft: EntryDraft(
                    kind: .journal,
                    title: "Fresh Shared Journal",
                    body: "Should survive a stale refresh.",
                    happenedAt: initialDate
                ),
                importedImageData: nil
            )
        }

        if let saveSnapshotStartedExpectation = cloudService.saveSnapshotStartedExpectation {
            await fulfillment(of: [saveSnapshotStartedExpectation], timeout: 1.0)
        }

        await store.refreshSharedRepositories(trigger: .foreground)

        XCTAssertEqual(
            store.journalEntries.filter { $0.title == "Fresh Shared Journal" }.count,
            1
        )

        let snapshotDuringSave = try XCTUnwrap(sharedStore.loadSnapshot())
        XCTAssertEqual(
            snapshotDuringSave.entries.filter { $0.title == "Fresh Shared Journal" }.count,
            1
        )

        cloudService.resumePausedSaveSnapshot()

        let didSave = await saveTask.value
        XCTAssertTrue(didSave)
        XCTAssertEqual(
            store.journalEntries.map(\.title),
            ["Fresh Shared Journal", "Earlier Shared Journal"]
        )

        let persistedSnapshot = try XCTUnwrap(sharedStore.loadSnapshot())
        XCTAssertEqual(
            persistedSnapshot.entries.map(\.title).sorted(),
            ["Earlier Shared Journal", "Fresh Shared Journal"]
        )
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

    @MainActor
    func testSharedRepositoryPushRefreshSkipsBadgeWhenNotificationScopeExcludesUpdatedEntry() async throws {
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
                isSharedUpdateNotificationEnabled: true,
                sharedUpdateNotificationScope: .journal
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
        await store.handleScenePhaseChange(.background)

        cloudService.loadedSnapshot = updatedSnapshot
        await store.refreshSharedRepositories(trigger: .push)

        XCTAssertEqual(store.entries.first?.title, "Shared Blog Updated")
        XCTAssertEqual(badgeCounts.last, 0)
        XCTAssertFalse(badgeCounts.contains(1))
    }

    @MainActor
    func testSharedRepositoryPushRefreshUsesOwnerScopeOverLocalPreference() async throws {
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
            updatedAt: initialDate,
            sharedUpdateNotificationScope: .blog
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
            updatedAt: updatedDate,
            sharedUpdateNotificationScope: .blog
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
                isSharedUpdateNotificationEnabled: true,
                sharedUpdateNotificationScope: .journal
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
        await store.handleScenePhaseChange(.background)

        cloudService.loadedSnapshot = updatedSnapshot
        await store.refreshSharedRepositories(trigger: .push)

        XCTAssertEqual(store.repositorySharedUpdateNotificationScope, .blog)
        XCTAssertEqual(store.effectiveCurrentRepositoryNotificationScope, .blog)
        XCTAssertEqual(badgeCounts.last, 1)
    }
}
