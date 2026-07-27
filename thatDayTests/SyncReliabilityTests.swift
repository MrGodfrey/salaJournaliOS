import CloudKit
import SwiftUI
import UIKit
import XCTest
@testable import thatDay

final class SyncReliabilityTests: AppStoreTestCase {
    @MainActor
    func testNotificationsDisabledStillConfiguresAndRunsBackgroundSynchronization() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "notification-independent-zone",
            zoneOwnerName: "_shared_owner_",
            shareRecordName: "notification-independent-share",
            role: .viewer
        )
        let repositoryID = descriptor.storageIdentifier
        let initialDate = fixtureDate("2026-07-20T09:00:00Z")
        let updatedDate = fixtureDate("2026-07-20T10:00:00Z")
        let entryID = UUID()
        let initialSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .journal,
                    title: "Before background sync",
                    body: "Initial body",
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
                    kind: .journal,
                    title: "After background sync",
                    body: "Updated body",
                    happenedAt: initialDate,
                    createdAt: initialDate,
                    updatedAt: updatedDate
                )
            ],
            updatedAt: updatedDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Notification Independent",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: initialSnapshot.updatedAt
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: initialSnapshot],
            preferences: AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-07-20T11:00:00Z") }
        )

        await store.loadIfNeeded()

        XCTAssertEqual(cloudService.ensuredSubscriptionDescriptors, [descriptor])
        XCTAssertFalse(try libraryStore.loadPreferences().isSharedUpdateNotificationEnabled)

        cloudService.loadedSnapshot = updatedSnapshot
        let result = await store.handleRemoteRepositoryChange(
            .zone(ownerName: "_shared_owner_", zoneName: "notification-independent-zone"),
            trigger: .push
        )

        XCTAssertEqual(result.rawValue, UIBackgroundFetchResult.newData.rawValue)
        XCTAssertEqual(
            try libraryStore.repositoryStore(for: repositoryID).loadSnapshot()?.entries.first?.title,
            "After background sync"
        )
    }

    @MainActor
    func testSubscriptionRepairValidatesEveryPrivateOwnerRepositoryAsVersionThree() async throws {
        let rootURL = makeTempDirectory()
        let validationDate = fixtureDate("2026-07-21T15:00:00Z")
        let firstDescriptor = RepositoryDescriptor(
            zoneName: "first-private-owner-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "first-private-share",
            role: .owner
        )
        let secondDescriptor = RepositoryDescriptor(
            zoneName: "second-private-owner-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "second-private-share",
            role: .owner
        )
        let firstSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(title: "First owner", happenedAt: validationDate)
            ],
            updatedAt: validationDate
        )
        let secondSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(title: "Second owner", happenedAt: validationDate)
            ],
            updatedAt: validationDate
        )
        let firstReference = RepositoryReference(
            id: firstDescriptor.storageIdentifier,
            displayName: "First Owner",
            descriptor: firstDescriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: validationDate
        )
        let secondReference = RepositoryReference(
            id: secondDescriptor.storageIdentifier,
            displayName: "Second Owner",
            descriptor: secondDescriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: validationDate
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [firstReference, secondReference],
            snapshotsByRepositoryID: [
                firstReference.id: firstSnapshot,
                secondReference.id: secondSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: firstReference.id
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshotsByRepositoryID = [
            firstReference.id: firstSnapshot,
            secondReference.id: secondSnapshot
        ]
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { validationDate }
        )

        await store.loadIfNeeded()

        XCTAssertEqual(
            Set(cloudService.ensuredSubscriptionDescriptors),
            Set([firstDescriptor, secondDescriptor])
        )
        let persistedOwners = try libraryStore.loadCatalog().filter {
            $0.descriptor.role == .owner
        }
        XCTAssertEqual(persistedOwners.count, 2)
        XCTAssertTrue(
            persistedOwners.allSatisfy {
                $0.subscriptionConfigurationVersion == 3 &&
                    $0.subscriptionValidatedAt == validationDate
            }
        )
    }

    @MainActor
    func testFailedPrivateRepairDoesNotBlockOrValidateSuccessfulSharedRepair() async throws {
        let rootURL = makeTempDirectory()
        let validationDate = fixtureDate("2026-07-26T21:00:00Z")
        let ownerDescriptor = RepositoryDescriptor(
            zoneName: "failed-private-repair-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "failed-private-repair-share",
            role: .owner
        )
        let viewerDescriptor = RepositoryDescriptor(
            zoneName: "successful-shared-repair-zone",
            zoneOwnerName: "_successful_shared_owner_",
            shareRecordName: "successful-shared-repair-share",
            role: .viewer
        )
        let ownerSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Owner", happenedAt: validationDate)],
            updatedAt: validationDate
        )
        let viewerSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Viewer", happenedAt: validationDate)],
            updatedAt: validationDate
        )
        let ownerReference = RepositoryReference(
            id: ownerDescriptor.storageIdentifier,
            displayName: "Owner",
            descriptor: ownerDescriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: validationDate,
            subscriptionConfigurationVersion: 2,
            subscriptionValidatedAt: validationDate
        )
        let viewerReference = RepositoryReference(
            id: viewerDescriptor.storageIdentifier,
            displayName: "Viewer",
            descriptor: viewerDescriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: validationDate,
            subscriptionConfigurationVersion: 2,
            subscriptionValidatedAt: validationDate
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [ownerReference, viewerReference],
            snapshotsByRepositoryID: [
                ownerReference.id: ownerSnapshot,
                viewerReference.id: viewerSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshotsByRepositoryID = [
            ownerReference.id: ownerSnapshot,
            viewerReference.id: viewerSnapshot
        ]
        cloudService.ensureSubscriptionErrorsByRole[.owner] =
            SimulatedSubscriptionRepairError.failed
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { validationDate }
        )

        await store.loadIfNeeded()

        let persisted = try libraryStore.loadCatalog()
        XCTAssertEqual(
            persisted.first(where: { $0.id == ownerReference.id })?
                .subscriptionConfigurationVersion,
            2
        )
        XCTAssertEqual(
            persisted.first(where: { $0.id == viewerReference.id })?
                .subscriptionConfigurationVersion,
            3
        )
        XCTAssertEqual(
            cloudService.ensuredSubscriptionDescriptors,
            [ownerDescriptor, viewerDescriptor]
        )
    }

    @MainActor
    func testFailedSubscriptionRepairIsAttemptedOnlyOncePerRunningProcess() async throws {
        let rootURL = makeTempDirectory()
        let validationDate = fixtureDate("2026-07-26T21:30:00Z")
        let descriptor = RepositoryDescriptor(
            zoneName: "single-attempt-zone",
            zoneOwnerName: "_single_attempt_owner_",
            shareRecordName: "single-attempt-share",
            role: .viewer
        )
        let snapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Single subscription attempt",
                    happenedAt: validationDate
                )
            ],
            updatedAt: validationDate
        )
        let reference = RepositoryReference(
            id: descriptor.storageIdentifier,
            displayName: "Single Attempt",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: validationDate,
            subscriptionConfigurationVersion: 2,
            subscriptionValidatedAt: validationDate
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [reference.id: snapshot],
            preferences: AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = snapshot
        cloudService.ensureSubscriptionError =
            SimulatedSubscriptionRepairError.failed
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { validationDate }
        )

        await store.loadIfNeeded()
        await store.handleScenePhaseChange(.active)
        await store.handleScenePhaseChange(.inactive)
        await store.handleScenePhaseChange(.active)

        XCTAssertEqual(
            cloudService.ensuredSubscriptionDescriptors,
            [descriptor]
        )
        XCTAssertEqual(
            try libraryStore.loadCatalog().first(where: { $0.id == reference.id })?
                .subscriptionConfigurationVersion,
            2
        )
    }

    @MainActor
    func testSuccessfulSubscriptionRepairCanRevalidateAfterSevenDaysInSameProcess() async throws {
        let rootURL = makeTempDirectory()
        let initialDate = fixtureDate("2026-07-18T21:30:00Z")
        var currentDate = initialDate
        let descriptor = RepositoryDescriptor(
            zoneName: "periodic-validation-zone",
            zoneOwnerName: "_periodic_validation_owner_",
            shareRecordName: "periodic-validation-share",
            role: .viewer
        )
        let snapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Periodic subscription validation",
                    happenedAt: initialDate
                )
            ],
            updatedAt: initialDate
        )
        let reference = RepositoryReference(
            id: descriptor.storageIdentifier,
            displayName: "Periodic Validation",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: initialDate,
            subscriptionConfigurationVersion: 2,
            subscriptionValidatedAt: initialDate
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [reference.id: snapshot],
            preferences: AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = snapshot
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { currentDate }
        )

        await store.loadIfNeeded()
        currentDate = initialDate.addingTimeInterval(8 * 24 * 60 * 60)
        await store.handleScenePhaseChange(.inactive)
        await store.handleScenePhaseChange(.active)

        XCTAssertEqual(
            cloudService.ensuredSubscriptionDescriptors,
            [descriptor, descriptor]
        )
        let persistedReference = try libraryStore.loadCatalog().first {
            $0.id == reference.id
        }
        XCTAssertEqual(
            persistedReference?.subscriptionConfigurationVersion,
            3
        )
        XCTAssertEqual(
            persistedReference?.subscriptionValidatedAt,
            currentDate
        )
    }

    @MainActor
    func testDeletedEntryCreatesRepositoryLevelUpdateNotification() throws {
        let snapshotDate = fixtureDate("2026-07-20T12:00:00Z")
        let store = try makeStore(now: snapshotDate)
        let descriptor = RepositoryDescriptor(
            zoneName: "deleted-entry-zone",
            zoneOwnerName: "_deleted_entry_owner_",
            shareRecordName: "deleted-entry-share",
            role: .viewer
        )
        let reference = RepositoryReference(
            id: descriptor.storageIdentifier,
            displayName: "Deletion Notification Repository",
            descriptor: descriptor,
            source: .shared
        )
        let deletedEntry = makeEntry(
            title: "Deleted on another device",
            happenedAt: snapshotDate
        )

        let notification = try XCTUnwrap(
            store.makeSharedRepositoryNotification(
                for: reference,
                previousEntries: [deletedEntry],
                latestEntries: [],
                repositoryNotificationScope: .all
            )
        )

        XCTAssertEqual(notification.repositoryID, reference.id)
        XCTAssertNil(notification.entryID)
        XCTAssertEqual(notification.body, L10n.string("An entry was deleted."))
    }

    @MainActor
    func testSharedDatabasePushRefreshesOnlyChangedRepositoryAndReturnsNewData() async throws {
        let rootURL = makeTempDirectory()
        let firstDescriptor = RepositoryDescriptor(
            zoneName: "unchanged-zone",
            zoneOwnerName: "_first_owner_",
            shareRecordName: "unchanged-share",
            role: .viewer
        )
        let secondDescriptor = RepositoryDescriptor(
            zoneName: "changed-zone",
            zoneOwnerName: "_second_owner_",
            shareRecordName: "changed-share",
            role: .editor
        )
        let firstRepositoryID = firstDescriptor.storageIdentifier
        let secondRepositoryID = secondDescriptor.storageIdentifier
        let initialDate = fixtureDate("2026-07-21T09:00:00Z")
        let updatedDate = fixtureDate("2026-07-21T10:00:00Z")
        let firstSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Unchanged repository", happenedAt: initialDate)],
            updatedAt: initialDate
        )
        let secondInitialSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Changed repository before push", happenedAt: initialDate)],
            updatedAt: initialDate
        )
        let secondUpdatedSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Changed repository after push", happenedAt: updatedDate)],
            updatedAt: updatedDate
        )
        let references = [
            RepositoryReference(
                id: firstRepositoryID,
                displayName: "Unchanged Repository",
                descriptor: firstDescriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: firstSnapshot.updatedAt
            ),
            RepositoryReference(
                id: secondRepositoryID,
                displayName: "Changed Repository",
                descriptor: secondDescriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: secondInitialSnapshot.updatedAt
            )
        ]
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: references,
            snapshotsByRepositoryID: [
                firstRepositoryID: firstSnapshot,
                secondRepositoryID: secondInitialSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshotsByRepositoryID = [
            firstRepositoryID: firstSnapshot,
            secondRepositoryID: secondInitialSnapshot
        ]
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-07-21T11:00:00Z") }
        )
        await store.loadIfNeeded()

        cloudService.loadedMetadataDescriptors.removeAll()
        cloudService.loadedDescriptors.removeAll()
        cloudService.changedZoneScopeRequests.removeAll()
        cloudService.changedZoneIDsByScope[.sharedDatabase] = [
            CloudRepositoryZoneIdentity(
                ownerName: "_second_owner_",
                zoneName: "changed-zone"
            )
        ]
        cloudService.loadedSnapshotsByRepositoryID[secondRepositoryID] = secondUpdatedSnapshot

        let result = await store.handleRemoteRepositoryChange(
            .database(.sharedDatabase),
            trigger: .push
        )

        XCTAssertEqual(result.rawValue, UIBackgroundFetchResult.newData.rawValue)
        XCTAssertEqual(cloudService.changedZoneScopeRequests, [.sharedDatabase])
        XCTAssertEqual(cloudService.loadedMetadataDescriptors, [secondDescriptor])
        XCTAssertEqual(cloudService.loadedDescriptors, [secondDescriptor])
        XCTAssertEqual(
            try libraryStore.repositoryStore(for: firstRepositoryID).loadSnapshot()?.entries.first?.title,
            "Unchanged repository"
        )
        XCTAssertEqual(
            try libraryStore.repositoryStore(for: secondRepositoryID).loadSnapshot()?.entries.first?.title,
            "Changed repository after push"
        )
        XCTAssertEqual(
            cloudService.acknowledgedZoneIDsByScope[.sharedDatabase],
            [[CloudRepositoryZoneIdentity(ownerName: "_second_owner_", zoneName: "changed-zone")]]
        )
    }

    @MainActor
    func testBackgroundRecoveryUsesDatabaseChangeTokensInsteadOfPollingEveryRepository() async throws {
        let rootURL = makeTempDirectory()
        let ownerDescriptor = RepositoryDescriptor(
            zoneName: "background-owner-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "background-owner-share",
            role: .owner
        )
        let viewerDescriptor = RepositoryDescriptor(
            zoneName: "background-viewer-zone",
            zoneOwnerName: "_background_viewer_owner_",
            shareRecordName: "background-viewer-share",
            role: .viewer
        )
        let snapshotDate = fixtureDate("2026-07-21T11:30:00Z")
        let ownerSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Owner snapshot", happenedAt: snapshotDate)],
            updatedAt: snapshotDate
        )
        let viewerSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Viewer snapshot", happenedAt: snapshotDate)],
            updatedAt: snapshotDate
        )
        let references = [
            RepositoryReference(
                id: ownerDescriptor.storageIdentifier,
                displayName: "Owner Repository",
                descriptor: ownerDescriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: snapshotDate
            ),
            RepositoryReference(
                id: viewerDescriptor.storageIdentifier,
                displayName: "Viewer Repository",
                descriptor: viewerDescriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: snapshotDate
            )
        ]
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: references,
            snapshotsByRepositoryID: [
                ownerDescriptor.storageIdentifier: ownerSnapshot,
                viewerDescriptor.storageIdentifier: viewerSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshotsByRepositoryID = [
            ownerDescriptor.storageIdentifier: ownerSnapshot,
            viewerDescriptor.storageIdentifier: viewerSnapshot
        ]
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-07-21T11:45:00Z") }
        )
        await store.loadIfNeeded()

        cloudService.loadedMetadataDescriptors.removeAll()
        cloudService.loadedDescriptors.removeAll()
        cloudService.changedZoneScopeRequests.removeAll()

        let result = await store.handleRemoteRepositoryChange(
            nil,
            trigger: .backgroundRecovery
        )

        XCTAssertEqual(result.rawValue, UIBackgroundFetchResult.noData.rawValue)
        XCTAssertEqual(
            cloudService.changedZoneScopeRequests,
            [.privateDatabase, .sharedDatabase]
        )
        XCTAssertTrue(cloudService.loadedMetadataDescriptors.isEmpty)
        XCTAssertTrue(cloudService.loadedDescriptors.isEmpty)
    }

    @MainActor
    func testDatabaseZoneChangeIsAcknowledgedOnlyAfterRepositoryRefreshSucceeds() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "retry-download-zone",
            zoneOwnerName: "_retry_download_owner_",
            shareRecordName: "retry-download-share",
            role: .viewer
        )
        let repositoryID = descriptor.storageIdentifier
        let initialDate = fixtureDate("2026-07-21T12:00:00Z")
        let updatedDate = fixtureDate("2026-07-21T13:00:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Before failed download", happenedAt: initialDate)],
            updatedAt: initialDate
        )
        let updatedSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "After successful retry", happenedAt: updatedDate)],
            updatedAt: updatedDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Retry Download Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: initialDate,
            lastKnownServerRecordChangeTag: "initial-change-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: initialSnapshot],
            preferences: AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let zoneID = CloudRepositoryZoneIdentity(
            ownerName: "_retry_download_owner_",
            zoneName: "retry-download-zone"
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "initial-change-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-07-21T14:00:00Z") }
        )
        await store.loadIfNeeded()

        cloudService.loadedMetadataDescriptors.removeAll()
        cloudService.loadedDescriptors.removeAll()
        cloudService.changedZoneScopeRequests.removeAll()
        cloudService.changedZoneIDsByScope[.sharedDatabase] = [zoneID]
        cloudService.loadedSnapshot = updatedSnapshot
        cloudService.metadataRecordChangeTag = "updated-change-tag"
        cloudService.loadMetadataError = SimulatedDownloadError.failed

        let failedResult = await store.handleRemoteRepositoryChange(
            .database(.sharedDatabase),
            trigger: .push
        )

        XCTAssertEqual(failedResult.rawValue, UIBackgroundFetchResult.failed.rawValue)
        XCTAssertEqual(cloudService.loadedMetadataDescriptors, [descriptor])
        XCTAssertTrue(cloudService.loadedDescriptors.isEmpty)
        XCTAssertNil(cloudService.acknowledgedZoneIDsByScope[.sharedDatabase])
        XCTAssertEqual(cloudService.changedZoneIDsByScope[.sharedDatabase], [zoneID])
        XCTAssertEqual(
            try libraryStore.repositoryStore(for: repositoryID).loadSnapshot()?.entries.first?.title,
            "Before failed download"
        )

        cloudService.loadMetadataError = nil
        cloudService.loadedMetadataDescriptors.removeAll()

        let retriedResult = await store.handleRemoteRepositoryChange(
            .database(.sharedDatabase),
            trigger: .push
        )

        XCTAssertEqual(retriedResult.rawValue, UIBackgroundFetchResult.newData.rawValue)
        XCTAssertEqual(cloudService.loadedMetadataDescriptors, [descriptor])
        XCTAssertEqual(cloudService.loadedDescriptors, [descriptor])
        XCTAssertEqual(cloudService.acknowledgedZoneIDsByScope[.sharedDatabase], [[zoneID]])
        XCTAssertEqual(cloudService.changedZoneIDsByScope[.sharedDatabase], [])
        XCTAssertEqual(
            try libraryStore.repositoryStore(for: repositoryID).loadSnapshot()?.entries.first?.title,
            "After successful retry"
        )
    }

    @MainActor
    func testOverlappingRefreshRequestsRunSerially() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "serialized-refresh-zone",
            zoneOwnerName: "_serialized_refresh_owner_",
            shareRecordName: "serialized-refresh-share",
            role: .viewer
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-21T14:30:00Z")
        let snapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Serialized refresh", happenedAt: snapshotDate)],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Serialized Refresh Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "serialized-change-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: snapshot],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = snapshot
        cloudService.metadataRecordChangeTag = "serialized-change-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-07-21T15:00:00Z") }
        )
        await store.loadIfNeeded()

        cloudService.loadedMetadataDescriptors.removeAll()
        cloudService.pauseLoadMetadata = true
        let firstMetadataRequest = expectation(
            description: "first refresh pauses while loading metadata"
        )
        cloudService.loadMetadataStartedExpectation = firstMetadataRequest

        let firstRefresh = Task { @MainActor in
            await store.refreshSharedRepositories(trigger: .manual)
        }
        await fulfillment(of: [firstMetadataRequest], timeout: 1.0)

        cloudService.loadMetadataStartedExpectation = nil
        let secondRefresh = Task { @MainActor in
            await store.refreshSharedRepositories(trigger: .manual)
        }
        for _ in 0..<100 {
            await Task.yield()
        }

        XCTAssertEqual(
            cloudService.loadedMetadataDescriptors.count,
            1,
            "A second refresh must wait instead of starting a concurrent CloudKit request."
        )

        cloudService.resumePausedLoadMetadata()
        _ = await firstRefresh.value
        _ = await secondRefresh.value

        XCTAssertEqual(cloudService.loadedMetadataDescriptors.count, 2)
    }

    @MainActor
    func testDeletedSharedZoneIsAcknowledgedAndLeavesCurrentRepositoryCachedReadOnly() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "deleted-shared-zone",
            zoneOwnerName: "_deleted_shared_owner_",
            shareRecordName: "deleted-shared-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-21T15:00:00Z")
        let deletionDate = fixtureDate("2026-07-21T16:00:00Z")
        let cachedSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Keep cached after deletion", happenedAt: snapshotDate)],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Deleted Shared Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "before-deletion-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: cachedSnapshot],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let zoneID = CloudRepositoryZoneIdentity(
            ownerName: "_deleted_shared_owner_",
            zoneName: "deleted-shared-zone"
        )
        let deletion = CloudRepositoryZoneDeletion(
            zoneID: zoneID,
            reason: .deleted
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = cachedSnapshot
        cloudService.metadataRecordChangeTag = "before-deletion-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { deletionDate }
        )
        await store.loadIfNeeded()
        XCTAssertTrue(store.canEditRepository)

        cloudService.loadedMetadataDescriptors.removeAll()
        cloudService.loadedDescriptors.removeAll()
        cloudService.changedZoneScopeRequests.removeAll()
        cloudService.deletedZonesByScope[.sharedDatabase] = [deletion]

        let result = await store.handleRemoteRepositoryChange(
            .database(.sharedDatabase),
            trigger: .push
        )

        XCTAssertEqual(result.rawValue, UIBackgroundFetchResult.newData.rawValue)
        XCTAssertTrue(cloudService.loadedMetadataDescriptors.isEmpty)
        XCTAssertTrue(cloudService.loadedDescriptors.isEmpty)
        XCTAssertEqual(
            cloudService.acknowledgedDeletedZonesByScope[.sharedDatabase],
            [[deletion]]
        )
        XCTAssertEqual(cloudService.deletedZonesByScope[.sharedDatabase], [])
        let unavailableReference = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertEqual(unavailableReference.cloudZoneUnavailableAt, deletionDate)
        XCTAssertFalse(store.canEditRepository)
        XCTAssertEqual(
            store.repositoryStatusTitle,
            L10n.string("Unavailable · Cached Read-Only")
        )
        XCTAssertEqual(
            try libraryStore.repositoryStore(for: repositoryID).loadSnapshot()?.entries.first?.title,
            "Keep cached after deletion"
        )

        _ = await store.handleRemoteRepositoryChange(
            .zone(
                ownerName: "_deleted_shared_owner_",
                zoneName: "deleted-shared-zone"
            ),
            trigger: .push
        )

        XCTAssertTrue(cloudService.loadedMetadataDescriptors.isEmpty)
        XCTAssertTrue(cloudService.loadedDescriptors.isEmpty)
    }

    @MainActor
    func testPurgedSharedZoneDeletesLocalRepositoryCatalogAndOutboxThenAcknowledges() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "purged-shared-zone",
            zoneOwnerName: "_purged_shared_owner_",
            shareRecordName: "purged-shared-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-21T16:30:00Z")
        let purgeDate = fixtureDate("2026-07-21T17:00:00Z")
        let cachedSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Delete this purged cache", happenedAt: snapshotDate)],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Purged Shared Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "before-purge-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: cachedSnapshot],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = cachedSnapshot
        cloudService.metadataRecordChangeTag = "before-purge-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { purgeDate }
        )
        await store.loadIfNeeded()

        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryStore.rootURL
        )
        let pendingSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Pending content must also be purged", happenedAt: purgeDate)],
            updatedAt: purgeDate
        )
        try outboxStore.save(
            CloudUploadOutboxRecord(
                repositoryID: repositoryID,
                descriptor: descriptor,
                displayName: "Purged Shared Repository",
                snapshot: pendingSnapshot,
                generation: 3,
                baseRecordChangeTag: "before-purge-tag",
                createdAt: purgeDate
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryStore.rootURL.path))
        XCTAssertNotNil(try outboxStore.load())

        let deletion = CloudRepositoryZoneDeletion(
            zoneID: CloudRepositoryZoneIdentity(
                ownerName: "_purged_shared_owner_",
                zoneName: "purged-shared-zone"
            ),
            reason: .purged
        )
        cloudService.loadedMetadataDescriptors.removeAll()
        cloudService.loadedDescriptors.removeAll()
        cloudService.deletedZonesByScope[.sharedDatabase] = [deletion]

        let result = await store.handleRemoteRepositoryChange(
            .database(.sharedDatabase),
            trigger: .push
        )

        XCTAssertEqual(result.rawValue, UIBackgroundFetchResult.newData.rawValue)
        XCTAssertTrue(cloudService.loadedMetadataDescriptors.isEmpty)
        XCTAssertTrue(cloudService.loadedDescriptors.isEmpty)
        XCTAssertTrue(cloudService.recreatedSnapshots.isEmpty)
        XCTAssertEqual(
            cloudService.acknowledgedDeletedZonesByScope[.sharedDatabase],
            [[deletion]]
        )
        XCTAssertEqual(cloudService.deletedZonesByScope[.sharedDatabase], [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repositoryStore.rootURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outboxStore.fileURL.path))
        XCTAssertNil(
            try libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertEqual(
            try libraryStore.loadPreferences().defaultRepositoryID,
            RepositoryReference.localRepositoryID
        )
        XCTAssertEqual(store.currentRepositoryID, RepositoryReference.localRepositoryID)
    }

    @MainActor
    func testOwnerEncryptedDataResetRecreatesPendingSnapshotUpdatesTagAndAcknowledges() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "encrypted-reset-owner-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "encrypted-reset-old-share",
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let localDate = fixtureDate("2026-07-21T17:30:00Z")
        let pendingDate = fixtureDate("2026-07-21T18:00:00Z")
        let resetDate = fixtureDate("2026-07-21T18:30:00Z")
        let localSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Older local owner snapshot", happenedAt: localDate)],
            updatedAt: localDate
        )
        let pendingSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Pending snapshot recreated after reset", happenedAt: pendingDate)],
            updatedAt: pendingDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Encrypted Reset Owner",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: localDate,
            lastKnownServerRecordChangeTag: "invalidated-owner-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: localSnapshot],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = localSnapshot
        cloudService.metadataRecordChangeTag = "invalidated-owner-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { resetDate }
        )
        await store.loadIfNeeded()

        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: repositoryStore.rootURL
        )
        try outboxStore.save(
            CloudUploadOutboxRecord(
                repositoryID: repositoryID,
                descriptor: descriptor,
                displayName: "Encrypted Reset Owner",
                snapshot: pendingSnapshot,
                generation: 8,
                baseRecordChangeTag: "invalidated-owner-tag",
                createdAt: pendingDate
            )
        )
        let recreatedDescriptor = RepositoryDescriptor(
            zoneName: "encrypted-reset-owner-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: nil,
            role: .owner
        )
        cloudService.recreateSnapshotResult = SavedRepositorySnapshot(
            descriptor: recreatedDescriptor,
            serverModifiedAt: resetDate,
            recordChangeTag: "recreated-owner-tag"
        )
        let deletion = CloudRepositoryZoneDeletion(
            zoneID: CloudRepositoryZoneIdentity(
                ownerName: CKCurrentUserDefaultName,
                zoneName: "encrypted-reset-owner-zone"
            ),
            reason: .encryptedDataReset
        )
        cloudService.loadedMetadataDescriptors.removeAll()
        cloudService.loadedDescriptors.removeAll()
        cloudService.savedSnapshots.removeAll()
        cloudService.deletedZonesByScope[.privateDatabase] = [deletion]

        let result = await store.handleRemoteRepositoryChange(
            .database(.privateDatabase),
            trigger: .push
        )

        XCTAssertEqual(result.rawValue, UIBackgroundFetchResult.newData.rawValue)
        XCTAssertTrue(cloudService.loadedMetadataDescriptors.isEmpty)
        XCTAssertTrue(cloudService.loadedDescriptors.isEmpty)
        XCTAssertTrue(cloudService.savedSnapshots.isEmpty)
        XCTAssertEqual(cloudService.recreatedDescriptors, [descriptor])
        let recreatedSnapshot = try XCTUnwrap(
            cloudService.recreatedSnapshots.first
        )
        XCTAssertEqual(
            recreatedSnapshot.entries,
            pendingSnapshot.entries
        )
        XCTAssertEqual(
            recreatedSnapshot.updatedAt,
            pendingSnapshot.updatedAt
        )
        XCTAssertNotNil(
            recreatedSnapshot.cloudUploadOperationID,
            "Encrypted reset recovery must carry a durable operation ID."
        )
        XCTAssertEqual(
            cloudService.acknowledgedDeletedZonesByScope[.privateDatabase],
            [[deletion]]
        )
        XCTAssertEqual(cloudService.deletedZonesByScope[.privateDatabase], [])
        let recreatedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertEqual(recreatedReference.descriptor, recreatedDescriptor)
        XCTAssertEqual(
            recreatedReference.lastKnownServerRecordChangeTag,
            "recreated-owner-tag"
        )
        XCTAssertEqual(recreatedReference.lastKnownServerModifiedAt, resetDate)
        XCTAssertNil(recreatedReference.pendingCloudUploadAt)
        XCTAssertNil(recreatedReference.pendingCloudUploadGeneration)
        XCTAssertNil(try outboxStore.load())
        XCTAssertEqual(store.repositoryDescriptor, recreatedDescriptor)
    }

    @MainActor
    func testParticipantEncryptedDataResetKeepsCacheReadOnlyWithoutRecreatingAndAcknowledges() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "encrypted-reset-participant-zone",
            zoneOwnerName: "_encrypted_reset_owner_",
            shareRecordName: "encrypted-reset-participant-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-21T19:00:00Z")
        let resetDate = fixtureDate("2026-07-21T19:30:00Z")
        let cachedSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Participant cache survives reset", happenedAt: snapshotDate)],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Encrypted Reset Participant",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "participant-reset-old-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: cachedSnapshot],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = cachedSnapshot
        cloudService.metadataRecordChangeTag = "participant-reset-old-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { resetDate }
        )
        await store.loadIfNeeded()
        XCTAssertTrue(store.canEditRepository)

        let deletion = CloudRepositoryZoneDeletion(
            zoneID: CloudRepositoryZoneIdentity(
                ownerName: "_encrypted_reset_owner_",
                zoneName: "encrypted-reset-participant-zone"
            ),
            reason: .encryptedDataReset
        )
        cloudService.loadedMetadataDescriptors.removeAll()
        cloudService.loadedDescriptors.removeAll()
        cloudService.deletedZonesByScope[.sharedDatabase] = [deletion]

        let result = await store.handleRemoteRepositoryChange(
            .database(.sharedDatabase),
            trigger: .push
        )

        XCTAssertEqual(result.rawValue, UIBackgroundFetchResult.newData.rawValue)
        XCTAssertTrue(cloudService.loadedMetadataDescriptors.isEmpty)
        XCTAssertTrue(cloudService.loadedDescriptors.isEmpty)
        XCTAssertTrue(cloudService.savedSnapshots.isEmpty)
        XCTAssertTrue(cloudService.recreatedSnapshots.isEmpty)
        XCTAssertEqual(
            cloudService.acknowledgedDeletedZonesByScope[.sharedDatabase],
            [[deletion]]
        )
        let unavailableReference = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertEqual(unavailableReference.cloudZoneUnavailableAt, resetDate)
        XCTAssertFalse(store.canEditRepository)
        XCTAssertEqual(
            try libraryStore.repositoryStore(for: repositoryID).loadSnapshot()?.entries.first?.title,
            "Participant cache survives reset"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: libraryStore.repositoryStore(for: repositoryID).rootURL.path
            )
        )
    }

    @MainActor
    func testAcceptedEditorSharePersistsServerBaselineAndUsesItForFirstUpload() async throws {
        let rootURL = makeTempDirectory()
        let acceptDate = fixtureDate("2026-07-21T20:00:00Z")
        let editDate = fixtureDate("2026-07-21T20:30:00Z")
        let descriptor = RepositoryDescriptor(
            zoneName: "accepted-editor-zone",
            zoneOwnerName: "_accepted_editor_owner_",
            shareRecordName: "accepted-editor-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let acceptedSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Accepted editor baseline", happenedAt: acceptDate)],
            updatedAt: acceptDate
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [],
            snapshotsByRepositoryID: [:],
            preferences: AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.acceptedSharedRepository = AcceptedSharedRepository(
            descriptor: descriptor,
            snapshot: acceptedSnapshot,
            displayName: "Accepted Editor Repository",
            serverModifiedAt: acceptDate,
            recordChangeTag: "accepted-editor-baseline-tag"
        )
        cloudService.loadedSnapshot = acceptedSnapshot
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { editDate }
        )
        await store.loadIfNeeded()

        store.incomingShareLink = "https://www.icloud.com/share/mock-editor-share"
        await store.acceptIncomingShareLink()

        XCTAssertEqual(store.currentRepositoryID, repositoryID)
        XCTAssertEqual(store.repositoryDescriptor.role, .editor)
        let acceptedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertEqual(
            acceptedReference.lastKnownServerRecordChangeTag,
            "accepted-editor-baseline-tag"
        )
        XCTAssertEqual(acceptedReference.lastKnownServerModifiedAt, acceptDate)

        cloudService.savedSnapshots.removeAll()
        cloudService.savedExpectedRecordChangeTags.removeAll()
        cloudService.savedRecordChangeTag = "accepted-editor-first-edit-tag"
        let firstUpload = expectation(description: "first editor upload uses accepted baseline")
        cloudService.saveSnapshotFinishedExpectation = firstUpload

        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "First edit after accepting share",
                body: "This upload must use the accepted server change tag.",
                happenedAt: editDate
            ),
            importedImageData: nil
        )

        XCTAssertTrue(didSave)
        await fulfillment(of: [firstUpload], timeout: 1.0)
        for _ in 0..<100 {
            if try libraryStore.loadCatalog().first(where: {
                $0.id == repositoryID
            })?.lastKnownServerRecordChangeTag == "accepted-editor-first-edit-tag" {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["accepted-editor-baseline-tag"]
        )
        XCTAssertEqual(
            cloudService.savedSnapshots.first?.entries.filter {
                $0.title == "First edit after accepting share"
            }.count,
            1
        )
        let uploadedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertEqual(
            uploadedReference.lastKnownServerRecordChangeTag,
            "accepted-editor-first-edit-tag"
        )
        XCTAssertNil(uploadedReference.pendingCloudUploadAt)
        XCTAssertNil(uploadedReference.pendingCloudUploadGeneration)
    }

    @MainActor
    func testChangedServerRecordChangeTagDownloadsSnapshotWithSameClientTimestampAndCount() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "change-tag-zone",
            zoneOwnerName: "_change_tag_owner_",
            shareRecordName: "change-tag-share",
            role: .viewer
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-22T09:00:00Z")
        let entryID = UUID()
        let initialSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "Old title",
                    body: "Old body",
                    happenedAt: snapshotDate,
                    createdAt: snapshotDate,
                    updatedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let serverSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: entryID,
                    kind: .blog,
                    title: "New title from server",
                    body: "New body from server",
                    happenedAt: snapshotDate,
                    createdAt: snapshotDate,
                    updatedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Change Tag Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "old-change-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: initialSnapshot],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "old-change-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-07-22T11:00:00Z") }
        )
        await store.loadIfNeeded()

        cloudService.loadedMetadataDescriptors.removeAll()
        cloudService.loadedDescriptors.removeAll()
        cloudService.loadedSnapshot = serverSnapshot
        cloudService.metadataRecordChangeTag = "new-change-tag"
        cloudService.metadataServerModifiedAt = fixtureDate("2026-07-22T10:30:00Z")

        let result = await store.refreshSharedRepositories(trigger: .manual)

        XCTAssertEqual(result.updatedRepositoryCount, 1)
        XCTAssertEqual(cloudService.loadedMetadataDescriptors, [descriptor])
        XCTAssertEqual(cloudService.loadedDescriptors, [descriptor])
        XCTAssertEqual(store.entries.first?.title, "New title from server")
        let persistedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertEqual(persistedReference.lastKnownServerRecordChangeTag, "new-change-tag")
        XCTAssertEqual(
            persistedReference.lastKnownServerModifiedAt,
            fixtureDate("2026-07-22T10:30:00Z")
        )
    }

    @MainActor
    func testRefreshSkipsDownloadingImagesAlreadyPresentInLocalCache() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "cached-image-zone",
            zoneOwnerName: "_cached_image_owner_",
            shareRecordName: "cached-image-share",
            role: .viewer
        )
        let repositoryID = descriptor.storageIdentifier
        let imageID = UUID()
        let imageReference = "\(imageID.uuidString).jpg"
        let snapshotDate = fixtureDate("2026-07-22T11:15:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: imageID,
                    kind: .journal,
                    title: "Cached image",
                    body: "Before",
                    happenedAt: snapshotDate,
                    imageReference: imageReference
                )
            ],
            updatedAt: snapshotDate
        )
        var remoteSnapshot = RepositorySnapshot(
            entries: [
                EntryRecord(
                    id: imageID,
                    kind: .journal,
                    title: "Cached image",
                    body: "Text changed without changing the image",
                    happenedAt: snapshotDate,
                    imageReference: imageReference
                )
            ],
            updatedAt: snapshotDate.addingTimeInterval(60)
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Cached Image Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "cached-image-old-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: initialSnapshot],
            preferences: AppPreferences(defaultRepositoryID: repositoryID)
        )
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let storedReference = try repositoryStore.storeImage(
            data: try XCTUnwrap(makePreviewImageData()),
            suggestedID: imageID
        )
        XCTAssertEqual(storedReference, imageReference)
        let localImageHashes = try repositoryStore.imageContentHashes(
            referencedBy: initialSnapshot.entries
        )
        remoteSnapshot.imageContentHashes = localImageHashes

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "cached-image-old-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate }
        )
        await store.loadIfNeeded()

        cloudService.availableImageContentHashesByLoad.removeAll()
        cloudService.loadedSnapshot = remoteSnapshot
        cloudService.metadataRecordChangeTag = "cached-image-new-tag"
        _ = await store.refreshSharedRepositories(trigger: .manual)

        XCTAssertEqual(
            cloudService.availableImageContentHashesByLoad,
            [localImageHashes]
        )
        XCTAssertEqual(
            try repositoryStore.loadSnapshot()?.entries.first?.body,
            "Text changed without changing the image"
        )
        XCTAssertNotNil(repositoryStore.imageURL(for: imageReference))
    }

    @MainActor
    func testPendingCloudUploadPersistsAfterFailureAndNextStoreRetriesAndClearsIt() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "durable-upload-zone",
            zoneOwnerName: "_durable_upload_owner_",
            shareRecordName: "durable-upload-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let initialDate = fixtureDate("2026-07-23T09:00:00Z")
        let saveDate = fixtureDate("2026-07-23T10:00:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Existing entry", happenedAt: initialDate)],
            updatedAt: initialDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Durable Upload Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: initialSnapshot.updatedAt
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: initialSnapshot],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let firstCloudService = MockCloudRepositoryService()
        firstCloudService.loadedSnapshot = initialSnapshot
        let firstStore = AppStore(
            libraryStore: libraryStore,
            cloudService: firstCloudService,
            now: { saveDate }
        )
        await firstStore.loadIfNeeded()

        let failedUpload = expectation(description: "first cloud upload fails")
        firstCloudService.saveSnapshotError = SimulatedUploadError.failed
        firstCloudService.saveSnapshotFinishedExpectation = failedUpload
        let didSave = await firstStore.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Locally durable entry",
                body: "Retry this after the app is rebuilt.",
                happenedAt: saveDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSave)
        await fulfillment(of: [failedUpload], timeout: 1.0)
        await Task.yield()

        let pendingReference = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertEqual(pendingReference.pendingCloudUploadAt, saveDate)
        let locallySavedSnapshot = try XCTUnwrap(
            libraryStore.repositoryStore(for: repositoryID).loadSnapshot()
        )
        XCTAssertEqual(
            locallySavedSnapshot.entries.filter { $0.title == "Locally durable entry" }.count,
            1
        )

        let retryCloudService = MockCloudRepositoryService()
        retryCloudService.loadedSnapshot = locallySavedSnapshot
        let retryStore = AppStore(
            libraryStore: libraryStore,
            cloudService: retryCloudService,
            now: { self.fixtureDate("2026-07-23T10:01:00Z") }
        )

        await retryStore.loadIfNeeded()

        XCTAssertEqual(retryCloudService.savedSnapshots.count, 1)
        XCTAssertEqual(
            retryCloudService.savedSnapshots.first?.entries.filter {
                $0.title == "Locally durable entry"
            }.count,
            1
        )
        let retriedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertNil(retriedReference.pendingCloudUploadAt)
    }

    @MainActor
    func testPersistedFalseConflictRebasesLocalAndRemoteUpdatesAndResumesOnLaunch() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "conflicting-upload-zone",
            zoneOwnerName: "_conflicting_upload_owner_",
            shareRecordName: "conflicting-upload-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let initialDate = fixtureDate("2026-07-23T11:00:00Z")
        let saveDate = fixtureDate("2026-07-23T11:30:00Z")
        let baselineEntry = makeEntry(
            title: "Server baseline entry",
            happenedAt: initialDate
        )
        let localEntry = makeEntry(
            title: "Local entry protected from overwrite",
            happenedAt: saveDate
        )
        let remoteEntry = makeEntry(
            title: "Girlfriend remote entry",
            happenedAt: saveDate
        )
        let baselineSnapshot = RepositorySnapshot(
            entries: [baselineEntry],
            updatedAt: initialDate
        )
        let pendingLocalSnapshot = RepositorySnapshot(
            entries: [baselineEntry, localEntry],
            updatedAt: saveDate
        )
        let remoteSnapshot = RepositorySnapshot(
            entries: [baselineEntry, remoteEntry],
            updatedAt: saveDate,
            cloudUploadOperationID: UUID()
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Conflicting Upload Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: saveDate,
            lastKnownServerRecordChangeTag:
                "persisted-baseline-tag",
            pendingCloudUploadAt: saveDate,
            pendingCloudUploadGeneration: 1,
            pendingCloudUploadBaseChangeTag:
                "persisted-baseline-tag",
            cloudUploadConflictServerChangeTag:
                "newer-server-tag",
            cloudUploadConflictDetectedAt: saveDate
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: pendingLocalSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false,
                cloudAccountUserRecordName: "account-a"
            )
        )
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: repositoryID)
                .rootURL
        )
        try outboxStore.save(
            CloudUploadOutboxRecord(
                repositoryID: repositoryID,
                descriptor: descriptor,
                displayName: reference.displayName,
                snapshot: pendingLocalSnapshot,
                generation: 1,
                baseRecordChangeTag:
                    "persisted-baseline-tag",
                baseSnapshot: baselineSnapshot,
                createdAt: saveDate
            )
        )

        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.loadedSnapshot = remoteSnapshot
        cloudService.metadataRecordChangeTag = "merged-tag"
        cloudService.loadedSnapshotEnvelope =
            LoadedRepositorySnapshot(
                snapshot: remoteSnapshot,
                metadata: RepositorySnapshotMetadata(
                    updatedAt: saveDate,
                    entryCount: remoteSnapshot.entries.count,
                    recordChangeTag: "newer-server-tag"
                )
            )
        cloudService.saveSnapshotErrors = [
            CloudRepositoryError.repositoryConflict(
                serverRecordChangeTag: "newer-server-tag"
            )
        ]
        cloudService.savedRecordChangeTag = "merged-tag"
        let completedUploads = expectation(
            description:
                "stale upload conflicts once and merged successor succeeds"
        )
        completedUploads.expectedFulfillmentCount = 2
        cloudService.saveSnapshotFinishedExpectation =
            completedUploads
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { saveDate }
        )

        await store.loadIfNeeded()
        await fulfillment(of: [completedUploads], timeout: 2)

        let completedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertNil(completedReference.pendingCloudUploadAt)
        XCTAssertNil(
            completedReference.pendingCloudUploadGeneration
        )
        XCTAssertNil(
            completedReference.cloudUploadConflictDetectedAt
        )
        XCTAssertNil(try outboxStore.load())
        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["persisted-baseline-tag", "newer-server-tag"]
        )
        let mergedSnapshot = try XCTUnwrap(
            libraryStore.repositoryStore(for: repositoryID).loadSnapshot()
        )
        XCTAssertEqual(
            Set(mergedSnapshot.entries.map(\.title)),
            Set([
                "Server baseline entry",
                "Local entry protected from overwrite",
                "Girlfriend remote entry"
            ])
        )
        XCTAssertEqual(
            Set(cloudService.savedSnapshots.last?.entries.map(
                \.title
            ) ?? []),
            Set([
                "Server baseline entry",
                "Local entry protected from overwrite",
                "Girlfriend remote entry"
            ])
        )
        XCTAssertEqual(
            store.entries.filter {
                $0.title == "Girlfriend remote entry"
            }.count,
            1
        )
    }

    @MainActor
    func testConflictRevalidationTreatsMatchingRemoteOperationAsCommitted() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "matching-operation-zone",
            zoneOwnerName: "_matching_operation_owner_",
            shareRecordName: "matching-operation-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-23T11:40:00Z")
        let pendingSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Already accepted remotely",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let operationID = UUID()
        let outbox = try CloudUploadOutboxRecord(
            repositoryID: repositoryID,
            descriptor: descriptor,
            displayName: "Matching Operation",
            snapshot: pendingSnapshot,
            generation: 1,
            baseRecordChangeTag: "tag-a",
            baseSnapshot: RepositorySnapshot(
                entries: [],
                updatedAt: snapshotDate.addingTimeInterval(-1)
            ),
            operationID: operationID,
            createdAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Matching Operation",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "tag-a",
            pendingCloudUploadAt: snapshotDate,
            pendingCloudUploadGeneration: 1,
            pendingCloudUploadBaseChangeTag: "tag-a"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: pendingSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                cloudAccountUserRecordName: "account-a"
            )
        )
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: repositoryID)
                .rootURL
        )
        try outboxStore.save(outbox)
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.loadedSnapshot = outbox.snapshot
        cloudService.metadataRecordChangeTag = "tag-b"
        cloudService.loadedSnapshotEnvelope =
            LoadedRepositorySnapshot(
                snapshot: outbox.snapshot,
                metadata: RepositorySnapshotMetadata(
                    updatedAt: snapshotDate,
                    entryCount: outbox.snapshot.entries.count,
                    recordChangeTag: "tag-b"
                )
            )
        cloudService.saveSnapshotErrors = [
            CloudRepositoryError.repositoryConflict(
                serverRecordChangeTag: "tag-b"
            )
        ]
        let attemptedUpload = expectation(
            description: "uncertain upload is revalidated"
        )
        cloudService.saveSnapshotFinishedExpectation =
            attemptedUpload
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate }
        )

        await store.loadIfNeeded()
        await fulfillment(of: [attemptedUpload], timeout: 2)

        XCTAssertEqual(cloudService.savedSnapshots.count, 1)
        XCTAssertNil(try outboxStore.load())
        let completedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first {
                $0.id == repositoryID
            }
        )
        XCTAssertNil(
            completedReference.pendingCloudUploadGeneration
        )
        XCTAssertEqual(
            completedReference.lastKnownServerRecordChangeTag,
            "tag-b"
        )
        XCTAssertEqual(
            try libraryStore.repositoryStore(for: repositoryID)
                .loadSnapshot()?.cloudUploadOperationID,
            operationID
        )
    }

    @MainActor
    func testConflictRevalidationAdvancesFromAcceptedPredecessorAndRetries() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "predecessor-operation-zone",
            zoneOwnerName: "_predecessor_operation_owner_",
            shareRecordName: "predecessor-operation-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-23T11:50:00Z")
        let predecessorID = UUID()
        let remoteSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Accepted predecessor",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate,
            cloudUploadOperationID: predecessorID
        )
        let pendingSnapshot = RepositorySnapshot(
            entries: remoteSnapshot.entries + [
                makeEntry(
                    title: "Successor edit",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let outbox = try CloudUploadOutboxRecord(
            repositoryID: repositoryID,
            descriptor: descriptor,
            displayName: "Predecessor Operation",
            snapshot: pendingSnapshot,
            generation: 2,
            baseRecordChangeTag: "tag-a",
            baseSnapshot: remoteSnapshot,
            predecessorOperationIDs: [predecessorID],
            createdAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Predecessor Operation",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "tag-a",
            pendingCloudUploadAt: snapshotDate,
            pendingCloudUploadGeneration: 2,
            pendingCloudUploadBaseChangeTag: "tag-a"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: pendingSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                cloudAccountUserRecordName: "account-a"
            )
        )
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: repositoryID)
                .rootURL
        )
        try outboxStore.save(outbox)
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.loadedSnapshot = pendingSnapshot
        cloudService.metadataRecordChangeTag = "tag-c"
        cloudService.loadedSnapshotEnvelope =
            LoadedRepositorySnapshot(
                snapshot: remoteSnapshot,
                metadata: RepositorySnapshotMetadata(
                    updatedAt: snapshotDate,
                    entryCount: remoteSnapshot.entries.count,
                    recordChangeTag: "tag-b"
                )
            )
        cloudService.saveSnapshotErrors = [
            CloudRepositoryError.repositoryConflict(
                serverRecordChangeTag: "tag-b"
            )
        ]
        cloudService.savedRecordChangeTag = "tag-c"
        let completedUploads = expectation(
            description:
                "predecessor is recognized and successor retries"
        )
        completedUploads.expectedFulfillmentCount = 2
        cloudService.saveSnapshotFinishedExpectation =
            completedUploads
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate }
        )

        await store.loadIfNeeded()
        await fulfillment(of: [completedUploads], timeout: 2)

        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["tag-a", "tag-b"]
        )
        XCTAssertEqual(
            cloudService.savedAcceptedPredecessorOperationIDs,
            [Set([predecessorID]), []]
        )
        XCTAssertNil(try outboxStore.load())
        XCTAssertNil(
            try libraryStore.loadCatalog().first {
                $0.id == repositoryID
            }?.pendingCloudUploadGeneration
        )
    }

    @MainActor
    func testConflictRefetchCannotOverwriteNewerLocalGeneration() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "conflict-generation-zone",
            zoneOwnerName: "_conflict_generation_owner_",
            shareRecordName: "conflict-generation-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-23T11:53:00Z")
        let baselineEntry = makeEntry(
            title: "Baseline",
            happenedAt: snapshotDate
        )
        let initialSnapshot = RepositorySnapshot(
            entries: [baselineEntry],
            updatedAt: snapshotDate
        )
        let remoteSnapshot = RepositorySnapshot(
            entries: [
                baselineEntry,
                makeEntry(
                    title: "Remote during refetch",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate,
            cloudUploadOperationID: UUID()
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Conflict Generation",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "tag-a"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: initialSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                cloudAccountUserRecordName: "account-a"
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "tag-a"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate }
        )
        await store.loadIfNeeded()
        cloudService.savedSnapshots.removeAll()
        cloudService.savedExpectedRecordChangeTags.removeAll()
        cloudService.loadedSnapshot = remoteSnapshot
        cloudService.metadataRecordChangeTag = "tag-c"
        cloudService.loadedSnapshotEnvelope =
            LoadedRepositorySnapshot(
                snapshot: remoteSnapshot,
                metadata: RepositorySnapshotMetadata(
                    updatedAt: snapshotDate,
                    entryCount: remoteSnapshot.entries.count,
                    recordChangeTag: "tag-b"
                )
            )
        cloudService.saveSnapshotErrors = [
            CloudRepositoryError.repositoryConflict(
                serverRecordChangeTag: "tag-b"
            ),
            CloudRepositoryError.repositoryConflict(
                serverRecordChangeTag: "tag-b"
            )
        ]
        cloudService.savedRecordChangeTag = "tag-c"

        let refetchStarted = expectation(
            description: "generation one conflict refetch pauses"
        )
        cloudService.pauseLoadSnapshotEnvelope = true
        cloudService.loadSnapshotEnvelopeStartedExpectation =
            refetchStarted
        let completedUploads = expectation(
            description:
                "both stale attempts and merged successor complete"
        )
        completedUploads.expectedFulfillmentCount = 3
        cloudService.saveSnapshotFinishedExpectation =
            completedUploads

        let didSaveFirstGeneration = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "First local generation",
                body: "Generation one",
                happenedAt: snapshotDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSaveFirstGeneration)
        await fulfillment(of: [refetchStarted], timeout: 2)
        cloudService.loadSnapshotEnvelopeStartedExpectation =
            nil

        let didSaveSecondGeneration = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Second local generation",
                body: "Generation two",
                happenedAt: snapshotDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSaveSecondGeneration)
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: repositoryID)
                .rootURL
        )
        let newerOutbox = try XCTUnwrap(outboxStore.load())
        XCTAssertEqual(newerOutbox.generation, 2)
        XCTAssertEqual(
            Set(newerOutbox.snapshot.entries.map(\.title)),
            Set([
                "Baseline",
                "First local generation",
                "Second local generation"
            ])
        )

        cloudService.resumePausedLoadSnapshotEnvelope()
        await fulfillment(of: [completedUploads], timeout: 2)
        cloudService.saveSnapshotFinishedExpectation = nil

        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["tag-a", "tag-a", "tag-b"]
        )
        XCTAssertEqual(
            Set(cloudService.savedSnapshots.last?.entries.map(
                \.title
            ) ?? []),
            Set([
                "Baseline",
                "First local generation",
                "Second local generation",
                "Remote during refetch"
            ])
        )
        XCTAssertEqual(
            Set(store.entries.map(\.title)),
            Set([
                "Baseline",
                "First local generation",
                "Second local generation",
                "Remote during refetch"
            ])
        )
        XCTAssertNil(try outboxStore.load())
    }

    @MainActor
    func testColdStartShowsCacheAndDurablyQueuesEditsUntilAccountVerificationCompletes() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "slow-account-zone",
            zoneOwnerName: "_slow_account_owner_",
            shareRecordName: "slow-account-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-23T11:55:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Immediately visible cache",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Slow Account",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "tag-a"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: initialSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                cloudAccountUserRecordName: "account-a"
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.pauseAccountAvailability = true
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "tag-b"
        cloudService.savedRecordChangeTag = "tag-b"
        let accountLookupStarted = expectation(
            description: "account lookup pauses after cache load"
        )
        cloudService.accountAvailabilityStartedExpectation =
            accountLookupStarted
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate }
        )

        let loadTask = Task {
            await store.loadIfNeeded()
        }
        await fulfillment(
            of: [accountLookupStarted],
            timeout: 2
        )

        XCTAssertEqual(
            store.entries.map(\.title),
            ["Immediately visible cache"]
        )
        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Written while account lookup is slow",
                body: "This must remain local until identity is known.",
                happenedAt: snapshotDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSave)
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertTrue(cloudService.savedSnapshots.isEmpty)
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: repositoryID)
                .rootURL
        )
        let pendingOutbox = try XCTUnwrap(
            outboxStore.load()
        )

        let uploadCompleted = expectation(
            description:
                "queued edit uploads after identity verification"
        )
        cloudService.saveSnapshotFinishedExpectation =
            uploadCompleted
        cloudService.resumePausedAccountAvailability()
        await loadTask.value
        await fulfillment(of: [uploadCompleted], timeout: 2)

        XCTAssertEqual(cloudService.savedSnapshots.count, 1)
        XCTAssertEqual(
            cloudService.savedSnapshots.first?
                .cloudUploadOperationID,
            pendingOutbox.operationID
        )
        XCTAssertNil(try outboxStore.load())
    }

    @MainActor
    func testTemporarilyUnavailableAccountSchedulesBoundedRetryAndResumesSameAccount() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "temporary-account-zone",
            zoneOwnerName: "_temporary_account_owner_",
            shareRecordName: "temporary-account-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-23T11:56:30Z")
        var currentDate = snapshotDate
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Available offline",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Temporary Account",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "tag-a"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: initialSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                cloudAccountUserRecordName: "account-a"
            )
        )
        let retrySleeper = ControlledSharedCloudRetrySleeper()
        var scheduledBackgroundDeadlines: [Date] = []
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability = .temporarilyUnavailable
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "tag-a"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { currentDate },
            sleepUntilSharedCloudRetry: { deadline in
                await retrySleeper.sleep(until: deadline)
            },
            scheduleBackgroundRefreshAfter: { deadline in
                scheduledBackgroundDeadlines.append(deadline)
            }
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.entries.map(\.title), ["Available offline"])
        XCTAssertEqual(cloudService.accountAvailabilityRequestCount, 1)
        for _ in 0..<100 {
            if !(await retrySleeper.deadlines()).isEmpty {
                break
            }
            await Task.yield()
        }
        let retryDeadline = snapshotDate.addingTimeInterval(60)
        let recordedRetryDeadlines = await retrySleeper.deadlines()
        XCTAssertEqual(recordedRetryDeadlines, [retryDeadline])
        XCTAssertEqual(scheduledBackgroundDeadlines, [retryDeadline])

        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        currentDate = retryDeadline
        await retrySleeper.resume()
        for _ in 0..<100 {
            if cloudService.accountAvailabilityRequestCount == 2,
               !cloudService
                .ensuredSubscriptionDescriptors.isEmpty {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(cloudService.accountAvailabilityRequestCount, 2)
        XCTAssertFalse(cloudService.ensuredSubscriptionDescriptors.isEmpty)
    }

    @MainActor
    func testAccountChangeDrainsInflightRefreshBeforeOldAccountCanOverwriteCache() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "account-refresh-race-zone",
            zoneOwnerName: "_account_refresh_race_owner_",
            shareRecordName: "account-refresh-race-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate =
            fixtureDate("2026-07-23T11:56:40Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Account A cache",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let remoteSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Late account A response",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate.addingTimeInterval(1)
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Account Refresh Race",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "tag-a"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: initialSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                cloudAccountUserRecordName: "account-a"
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "tag-a"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate }
        )
        await store.loadIfNeeded()

        cloudService.loadedSnapshot = remoteSnapshot
        cloudService.metadataRecordChangeTag = "tag-b"
        let zoneID = CloudRepositoryZoneIdentity(
            ownerName:
                try XCTUnwrap(descriptor.zoneOwnerName),
            zoneName: try XCTUnwrap(descriptor.zoneName)
        )
        cloudService.changedZoneIDsByScope[
            .sharedDatabase
        ] = [zoneID]
        cloudService.pauseLoadMetadata = true
        let refreshStarted = expectation(
            description: "account A refresh is in flight"
        )
        cloudService.loadMetadataStartedExpectation =
            refreshStarted
        let refreshTask = Task {
            await store.refreshSharedRepositories(
                trigger: .push,
                target: .database(.sharedDatabase)
            )
        }
        await fulfillment(of: [refreshStarted], timeout: 2)
        cloudService.loadMetadataStartedExpectation = nil

        cloudService.accountAvailability =
            .available(userRecordName: "account-b")
        let accountChangeTask = Task {
            await store.handleCloudAccountChange()
        }
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertEqual(
            cloudService.accountAvailabilityRequestCount,
            1,
            "Account lookup must wait until the old refresh drains."
        )

        cloudService.resumePausedLoadMetadata()
        _ = await refreshTask.value
        await accountChangeTask.value

        let cachedSnapshot = try XCTUnwrap(
            libraryStore.repositoryStore(
                for: repositoryID
            ).loadSnapshot()
        )
        XCTAssertEqual(
            cachedSnapshot.entries.map(\.title),
            ["Account A cache"]
        )
        XCTAssertEqual(
            try libraryStore.loadCatalog().first {
                $0.id == repositoryID
            }?.lastKnownServerRecordChangeTag,
            "tag-a"
        )
        XCTAssertTrue(
            cloudService
                .acknowledgedZoneIDsByScope[
                    .sharedDatabase
                ]?.isEmpty ?? true
        )
    }

    @MainActor
    func testLateShareAcceptanceIsRequeuedAcrossAccountChange() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate =
            fixtureDate("2026-07-23T11:56:50Z")
        let acceptedDescriptor = RepositoryDescriptor(
            zoneName: "late-share-zone",
            zoneOwnerName: "_late_share_owner_",
            shareRecordName: "late-share-record",
            role: .viewer
        )
        let acceptedSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Accepted on account A",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.acceptedSharedRepository =
            AcceptedSharedRepository(
                descriptor: acceptedDescriptor,
                snapshot: acceptedSnapshot,
                displayName: "Late Share",
                recordChangeTag: "accepted-tag"
            )
        let store = try makeStore(
            now: snapshotDate,
            entries: [],
            rootURL: rootURL,
            cloudService: cloudService,
            preferences: AppPreferences(
                cloudAccountUserRecordName: "account-a"
            )
        )
        await store.loadIfNeeded()

        let shareURL = try XCTUnwrap(
            URL(
                string:
                    "https://www.icloud.com/share/late-account-share"
            )
        )
        store.incomingShareLink = shareURL.absoluteString
        cloudService.pauseAcceptShare = true
        let acceptanceStarted = expectation(
            description: "account A share acceptance is in flight"
        )
        cloudService.acceptShareStartedExpectation =
            acceptanceStarted
        let acceptanceTask = Task {
            await store.acceptIncomingShareLink()
        }
        await fulfillment(
            of: [acceptanceStarted],
            timeout: 2
        )
        cloudService.acceptShareStartedExpectation = nil

        cloudService.accountAvailability =
            .available(userRecordName: "account-b")
        await store.handleCloudAccountChange()
        cloudService.resumePausedAcceptShare()
        await acceptanceTask.value

        XCTAssertEqual(
            store.currentRepositoryID,
            RepositoryReference.localRepositoryID
        )
        XCTAssertFalse(
            store.sortedRepositories.contains {
                $0.id ==
                    acceptedDescriptor.storageIdentifier
            }
        )
        XCTAssertEqual(cloudService.acceptedShareURLs, [shareURL])

        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        await store.handleCloudAccountChange()

        XCTAssertEqual(
            cloudService.acceptedShareURLs,
            [shareURL, shareURL]
        )
        XCTAssertEqual(
            store.currentRepositoryID,
            acceptedDescriptor.storageIdentifier
        )
        XCTAssertEqual(
            store.entries.map(\.title),
            ["Accepted on account A"]
        )
    }

    @MainActor
    func testStaleTransitionResetCannotUnquarantineDifferentAccount() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "stale-reset-zone",
            zoneOwnerName: "_stale_reset_owner_",
            shareRecordName: "stale-reset-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate =
            fixtureDate("2026-07-23T11:56:55Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Before stale reset",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Stale Reset",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "tag-a"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: initialSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                cloudAccountUserRecordName: "account-a"
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "tag-a"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate }
        )
        await store.loadIfNeeded()
        cloudService.savedSnapshots.removeAll()

        cloudService.pauseResetRemoteChangeTracking = true
        let resetStarted = expectation(
            description: "account A tracking reset is in flight"
        )
        cloudService
            .resetRemoteChangeTrackingStartedExpectation =
            resetStarted
        let firstTransition = Task {
            await store.handleCloudAccountChange()
        }
        await fulfillment(of: [resetStarted], timeout: 2)
        cloudService
            .resetRemoteChangeTrackingStartedExpectation = nil

        cloudService.accountAvailability =
            .available(userRecordName: "account-b")
        await store.handleCloudAccountChange()

        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Must stay quarantined",
                body:
                    "A stale reset may not upload this to account B.",
                happenedAt: snapshotDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSave)
        cloudService.resumePausedResetRemoteChangeTracking()
        await firstTransition.value
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertTrue(cloudService.savedSnapshots.isEmpty)
        XCTAssertNotNil(
            try CloudUploadOutboxStore(
                repositoryRootURL: libraryStore
                    .repositoryStore(for: repositoryID)
                    .rootURL
            ).load()
        )
    }

    @MainActor
    func testUpgradeWithoutStoredAccountIdentityRequiresExplicitConfirmation() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "identity-migration-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "identity-migration-share",
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate =
            fixtureDate("2026-07-23T11:56:58Z")
        let localSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Existing account A journal",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Identity Migration",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "account-a-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: localSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID
            )
        )
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: repositoryID)
                .rootURL
        )
        try outboxStore.save(
            CloudUploadOutboxRecord(
                repositoryID: repositoryID,
                descriptor: descriptor,
                displayName: reference.displayName,
                snapshot: localSnapshot,
                generation: 1,
                baseRecordChangeTag: "account-a-tag",
                baseSnapshot: localSnapshot,
                createdAt: snapshotDate
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService
            .requiresExplicitAccountIdentityMigrationConfirmation =
            true
        cloudService.accountAvailability =
            .available(userRecordName: "possibly-account-b")
        cloudService.loadedSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Different account B content",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        cloudService.metadataRecordChangeTag = "account-b-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate }
        )

        await store.loadIfNeeded()

        XCTAssertTrue(
            store
                .isCloudAccountMigrationConfirmationPresented
        )
        XCTAssertEqual(
            store.entries.map(\.title),
            ["Existing account A journal"]
        )
        XCTAssertTrue(cloudService.savedSnapshots.isEmpty)
        XCTAssertTrue(
            cloudService.loadedMetadataDescriptors.isEmpty
        )
        XCTAssertNil(
            try libraryStore.loadPreferences()
                .cloudAccountUserRecordName
        )
        XCTAssertNotNil(try outboxStore.load())
    }

    @MainActor
    func testColdLaunchShareDeliveryPreservesExistingCatalogUntilIdentityConfirmation() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate =
            fixtureDate("2026-07-23T11:56:59Z")
        let existingDescriptor = RepositoryDescriptor(
            zoneName: "existing-catalog-zone",
            zoneOwnerName: "_existing_catalog_owner_",
            shareRecordName: "existing-catalog-share",
            role: .viewer
        )
        let existingSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Existing catalog journal",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let existingReference = RepositoryReference(
            id: existingDescriptor.storageIdentifier,
            displayName: "Existing Catalog",
            descriptor: existingDescriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "existing-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [existingReference],
            snapshotsByRepositoryID: [
                existingReference.id: existingSnapshot
            ],
            preferences: AppPreferences()
        )
        let acceptedDescriptor = RepositoryDescriptor(
            zoneName: "cold-share-zone",
            zoneOwnerName: "_cold_share_owner_",
            shareRecordName: "cold-share-record",
            role: .viewer
        )
        let acceptedSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Cold delivered share",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let cloudService = MockCloudRepositoryService()
        cloudService
            .requiresExplicitAccountIdentityMigrationConfirmation =
            true
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.acceptedSharedRepository =
            AcceptedSharedRepository(
                descriptor: acceptedDescriptor,
                snapshot: acceptedSnapshot,
                displayName: "Cold Share",
                recordChangeTag: "accepted-tag"
            )
        cloudService.loadedSnapshotsByRepositoryID = [
            existingReference.id: existingSnapshot,
            acceptedDescriptor.storageIdentifier:
                acceptedSnapshot
        ]
        cloudService.metadataRecordChangeTag = "existing-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate }
        )
        let metadata = try makeShareMetadata()

        // Deliberately deliver the system share before ContentView's
        // loadIfNeeded task, matching the unordered cold-launch SwiftUI tasks.
        await store.acceptShare(metadata: metadata)

        XCTAssertEqual(
            cloudService.acceptedShareMetadataCount,
            0
        )
        XCTAssertTrue(
            store
                .isCloudAccountMigrationConfirmationPresented
        )
        XCTAssertEqual(
            Set(try libraryStore.loadCatalog().map(\.id)),
            Set([
                RepositoryReference.localRepositoryID,
                existingReference.id
            ])
        )
        XCTAssertEqual(
            try libraryStore.repositoryStore(
                for: existingReference.id
            ).loadSnapshot()?.entries.map(\.title),
            ["Existing catalog journal"]
        )

        await store
            .confirmCurrentICloudAccountForMigration()

        XCTAssertEqual(
            cloudService.acceptedShareMetadataCount,
            1
        )
        XCTAssertEqual(
            Set(try libraryStore.loadCatalog().map(\.id)),
            Set([
                RepositoryReference.localRepositoryID,
                existingReference.id,
                acceptedDescriptor.storageIdentifier
            ])
        )
        XCTAssertEqual(
            store.currentRepositoryID,
            acceptedDescriptor.storageIdentifier
        )
    }

    @MainActor
    func testDifferentICloudAccountQuarantinesNewEditsUntilOriginalAccountReturns() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "account-quarantine-zone",
            zoneOwnerName: "_account_quarantine_owner_",
            shareRecordName: "account-quarantine-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-23T11:57:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Original account cache",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Account Quarantine",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "tag-a"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: initialSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                cloudAccountUserRecordName: "account-a"
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "tag-a"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { snapshotDate }
        )
        await store.loadIfNeeded()
        cloudService.savedSnapshots.removeAll()

        cloudService.accountAvailability =
            .available(userRecordName: "account-b")
        await store.handleCloudAccountChange()
        XCTAssertEqual(
            cloudService.resetRemoteChangeTrackingCount,
            0
        )

        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Local edit while wrong account is active",
                body: "Never upload this into account B.",
                happenedAt: snapshotDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSave)
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertTrue(cloudService.savedSnapshots.isEmpty)
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: repositoryID)
                .rootURL
        )
        let quarantinedOutbox = try XCTUnwrap(
            outboxStore.load()
        )

        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.savedRecordChangeTag = "tag-c"
        cloudService.metadataRecordChangeTag = "tag-c"
        let uploadCompleted = expectation(
            description:
                "original account resumes quarantined upload"
        )
        cloudService.saveSnapshotFinishedExpectation =
            uploadCompleted
        await store.handleCloudAccountChange()
        await fulfillment(of: [uploadCompleted], timeout: 2)

        XCTAssertEqual(
            cloudService.resetRemoteChangeTrackingCount,
            1
        )
        XCTAssertEqual(cloudService.savedSnapshots.count, 1)
        XCTAssertEqual(
            cloudService.savedSnapshots.first?
                .cloudUploadOperationID,
            quarantinedOutbox.operationID
        )
        XCTAssertNil(try outboxStore.load())
    }

    @MainActor
    func testAccountLookupFailureCancelsStaleWriterThenRetriesFullTransitionRecovery() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "account-retry-zone",
            zoneOwnerName: "_account_retry_owner_",
            shareRecordName: "account-retry-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-23T11:58:00Z")
        var currentDate = snapshotDate
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Before account notification",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Account Retry",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate,
            lastKnownServerRecordChangeTag: "tag-a"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [
                repositoryID: initialSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                cloudAccountUserRecordName: "account-a"
            )
        )
        let retrySleeper = ControlledSharedCloudRetrySleeper()
        var scheduledBackgroundDeadlines: [Date] = []
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "tag-a"
        cloudService.savedRecordChangeTag = "tag-b"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { currentDate },
            sleepUntilSharedCloudRetry: { deadline in
                await retrySleeper.sleep(until: deadline)
            },
            scheduleBackgroundRefreshAfter: { deadline in
                scheduledBackgroundDeadlines.append(deadline)
            }
        )
        await store.loadIfNeeded()
        cloudService.ensuredSubscriptionDescriptors.removeAll()

        let staleUploadStarted = expectation(
            description: "old-account writer is in flight"
        )
        cloudService.pauseSaveSnapshot = true
        cloudService.saveSnapshotStartedExpectation =
            staleUploadStarted
        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Durable through account lookup failure",
                body: "The late response must not clear this outbox.",
                happenedAt: snapshotDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSave)
        await fulfillment(of: [staleUploadStarted], timeout: 2)
        cloudService.saveSnapshotStartedExpectation = nil
        let outboxStore = CloudUploadOutboxStore(
            repositoryRootURL: libraryStore
                .repositoryStore(for: repositoryID)
                .rootURL
        )
        let pendingOutbox = try XCTUnwrap(
            outboxStore.load()
        )

        cloudService.accountAvailabilityError =
            SimulatedAccountLookupError.failed
        let accountChangeTask = Task {
            await store.handleCloudAccountChange()
        }
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertEqual(
            cloudService.accountAvailabilityRequestCount,
            1,
            "The handler must drain the writer before starting account lookup."
        )
        cloudService.resumePausedSaveSnapshot()
        await accountChangeTask.value

        XCTAssertEqual(cloudService.savedSnapshots.count, 1)
        XCTAssertEqual(
            try outboxStore.load()?.operationID,
            pendingOutbox.operationID
        )
        XCTAssertEqual(
            try libraryStore.loadCatalog().first {
                $0.id == repositoryID
            }?.pendingCloudUploadGeneration,
            pendingOutbox.generation
        )
        XCTAssertEqual(
            cloudService.resetRemoteChangeTrackingCount,
            0
        )

        for _ in 0..<100 {
            if !(await retrySleeper.deadlines()).isEmpty {
                break
            }
            await Task.yield()
        }
        let retryDeadline = snapshotDate.addingTimeInterval(60)
        let recordedRetryDeadlines =
            await retrySleeper.deadlines()
        XCTAssertEqual(
            recordedRetryDeadlines,
            [retryDeadline]
        )
        XCTAssertEqual(
            scheduledBackgroundDeadlines,
            [retryDeadline]
        )

        cloudService.accountAvailabilityError = nil
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.metadataRecordChangeTag = "tag-b"
        let recoveredUploadFinished = expectation(
            description:
                "account retry resets tracking and resumes upload"
        )
        cloudService.saveSnapshotFinishedExpectation =
            recoveredUploadFinished
        currentDate = retryDeadline
        await retrySleeper.resume()
        await fulfillment(
            of: [recoveredUploadFinished],
            timeout: 2
        )
        cloudService.saveSnapshotFinishedExpectation = nil

        XCTAssertEqual(
            cloudService.resetRemoteChangeTrackingCount,
            1
        )
        XCTAssertEqual(
            cloudService.savedSnapshots.count,
            2
        )
        XCTAssertEqual(
            cloudService.savedSnapshots.last?
                .cloudUploadOperationID,
            pendingOutbox.operationID
        )
        XCTAssertEqual(
            cloudService.ensuredSubscriptionDescriptors,
            [descriptor]
        )
        XCTAssertNil(try outboxStore.load())
    }

    @MainActor
    func testIncomingShareWaitsForVerifiedICloudIdentity() async throws {
        let rootURL = makeTempDirectory()
        let snapshotDate = fixtureDate("2026-07-23T11:59:00Z")
        let acceptedDescriptor = RepositoryDescriptor(
            zoneName: "deferred-share-zone",
            zoneOwnerName: "_deferred_share_owner_",
            shareRecordName: "deferred-share-record",
            role: .viewer
        )
        let acceptedSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Accepted only after verification",
                    happenedAt: snapshotDate
                )
            ],
            updatedAt: snapshotDate
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.accountAvailability =
            .available(userRecordName: "account-a")
        cloudService.pauseAccountAvailability = true
        cloudService.accountAvailabilityStartedExpectation =
            expectation(
                description: "account verification pauses"
            )
        cloudService.acceptedSharedRepository =
            AcceptedSharedRepository(
                descriptor: acceptedDescriptor,
                snapshot: acceptedSnapshot,
                displayName: "Deferred Share",
                recordChangeTag: "accepted-tag"
            )
        let store = try makeStore(
            now: snapshotDate,
            entries: [],
            rootURL: rootURL,
            cloudService: cloudService,
            preferences: AppPreferences(
                cloudAccountUserRecordName: "account-a"
            )
        )
        let metadata = try makeShareMetadata()
        let loadTask = Task {
            await store.loadIfNeeded()
        }
        await fulfillment(
            of: [
                try XCTUnwrap(
                    cloudService
                        .accountAvailabilityStartedExpectation
                )
            ],
            timeout: 2
        )

        await store.acceptShare(metadata: metadata)
        XCTAssertEqual(
            cloudService.acceptedShareMetadataCount,
            0
        )

        cloudService.resumePausedAccountAvailability()
        await loadTask.value

        XCTAssertEqual(
            cloudService.acceptedShareMetadataCount,
            1
        )
        XCTAssertEqual(
            store.currentRepositoryID,
            acceptedDescriptor.storageIdentifier
        )
        XCTAssertEqual(
            store.entries.map(\.title),
            ["Accepted only after verification"]
        )
    }

    @MainActor
    func testNewerPendingUploadIsNotClearedWhenAnOlderUploadFinishes() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "overlapping-upload-zone",
            zoneOwnerName: "_overlapping_upload_owner_",
            shareRecordName: "overlapping-upload-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let initialDate = fixtureDate("2026-07-23T12:00:00Z")
        let saveDate = fixtureDate("2026-07-23T13:00:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Existing entry", happenedAt: initialDate)],
            updatedAt: initialDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Overlapping Upload Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: initialSnapshot.updatedAt,
            lastKnownServerRecordChangeTag: "initial-overlap-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: initialSnapshot],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "initial-overlap-tag"
        cloudService.savedRecordChangeTag = "first-upload-tag"
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { saveDate }
        )
        await store.loadIfNeeded()

        let firstUploadStarted = expectation(description: "first upload pauses")
        cloudService.pauseSaveSnapshot = true
        cloudService.saveSnapshotStartedExpectation = firstUploadStarted
        let firstSaveResult = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "First pending entry",
                body: "First body",
                happenedAt: saveDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(firstSaveResult)
        await fulfillment(of: [firstUploadStarted], timeout: 1.0)

        let secondSaveResult = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Second pending entry",
                body: "Second body",
                happenedAt: saveDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(secondSaveResult)

        let secondUploadStarted = expectation(description: "second upload pauses")
        cloudService.saveSnapshotStartedExpectation = secondUploadStarted
        cloudService.resumePausedSaveSnapshot()
        cloudService.pauseSaveSnapshot = true
        await fulfillment(of: [secondUploadStarted], timeout: 1.0)

        let referenceBetweenUploads = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertNotNil(referenceBetweenUploads.pendingCloudUploadAt)
        XCTAssertEqual(referenceBetweenUploads.pendingCloudUploadGeneration, 2)

        let secondUploadFinished = expectation(description: "second upload finishes")
        cloudService.saveSnapshotFinishedExpectation = secondUploadFinished
        cloudService.resumePausedSaveSnapshot()
        await fulfillment(of: [secondUploadFinished], timeout: 1.0)
        await Task.yield()

        let completedReference = try XCTUnwrap(
            libraryStore.loadCatalog().first(where: { $0.id == repositoryID })
        )
        XCTAssertNil(completedReference.pendingCloudUploadAt)
        XCTAssertNil(completedReference.pendingCloudUploadGeneration)
        XCTAssertEqual(cloudService.savedSnapshots.count, 2)
        XCTAssertEqual(
            cloudService.savedExpectedRecordChangeTags,
            ["initial-overlap-tag", "first-upload-tag"]
        )
        XCTAssertEqual(
            cloudService.savedSnapshots.last?.entries.filter {
                $0.title == "Second pending entry"
            }.count,
            1
        )
    }

    @MainActor
    func testCloudRetryAfterSurvivesStoreReconstruction() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "retry-after-zone",
            zoneOwnerName: "_retry_after_owner_",
            shareRecordName: "retry-after-share",
            role: .viewer
        )
        let repositoryID = descriptor.storageIdentifier
        let snapshotDate = fixtureDate("2026-07-24T09:00:00Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Rate limited repository", happenedAt: snapshotDate)],
            updatedAt: snapshotDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Rate Limited Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: snapshotDate
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: initialSnapshot],
            preferences: AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
        let requestDate = fixtureDate("2026-07-24T12:00:00Z")
        let firstCloudService = MockCloudRepositoryService()
        firstCloudService.loadedSnapshot = initialSnapshot
        let firstStore = AppStore(
            libraryStore: libraryStore,
            cloudService: firstCloudService,
            now: { requestDate }
        )
        await firstStore.loadIfNeeded()

        firstCloudService.loadedMetadataDescriptors.removeAll()
        firstCloudService.loadMetadataError = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.requestRateLimited.rawValue,
            userInfo: [CKErrorRetryAfterKey: 120]
        )
        _ = await firstStore.refreshSharedRepositories(trigger: .manual)

        XCTAssertEqual(firstCloudService.loadedMetadataDescriptors, [descriptor])
        XCTAssertEqual(
            try libraryStore.loadPreferences().cloudRetryAfter,
            requestDate.addingTimeInterval(120)
        )

        let reconstructedCloudService = MockCloudRepositoryService()
        reconstructedCloudService.loadedSnapshot = initialSnapshot
        let reconstructedStore = AppStore(
            libraryStore: libraryStore,
            cloudService: reconstructedCloudService,
            now: { requestDate.addingTimeInterval(60) }
        )

        await reconstructedStore.loadIfNeeded()
        _ = await reconstructedStore.refreshSharedRepositories(trigger: .manual)

        XCTAssertTrue(reconstructedCloudService.loadedMetadataDescriptors.isEmpty)
        XCTAssertTrue(reconstructedCloudService.loadedDescriptors.isEmpty)
        XCTAssertTrue(
            reconstructedStore.alertMessage?.contains(
                "CloudKit is temporarily limiting sync"
            ) == true
        )
    }

    @MainActor
    func testRateLimitedUploadRetriesOnceWhenPersistedDeadlineExpires() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "retry-deadline-zone",
            zoneOwnerName: "_retry_deadline_owner_",
            shareRecordName: "retry-deadline-share",
            role: .editor
        )
        let repositoryID = descriptor.storageIdentifier
        let initialDate = fixtureDate("2026-07-24T13:00:00Z")
        let retryAfter: TimeInterval = 120
        var currentDate = initialDate
        let initialSnapshot = RepositorySnapshot(
            entries: [
                makeEntry(
                    title: "Before rate limit",
                    happenedAt: initialDate
                )
            ],
            updatedAt: initialDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Retry Deadline Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: initialDate,
            lastKnownServerRecordChangeTag: "retry-baseline"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: initialSnapshot],
            preferences: AppPreferences(defaultRepositoryID: repositoryID)
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "retry-baseline"
        let retrySleeper = ControlledSharedCloudRetrySleeper()
        var scheduledBackgroundDeadlines: [Date] = []
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { currentDate },
            sleepUntilSharedCloudRetry: { deadline in
                await retrySleeper.sleep(until: deadline)
            },
            scheduleBackgroundRefreshAfter: { deadline in
                scheduledBackgroundDeadlines.append(deadline)
            }
        )
        await store.loadIfNeeded()

        cloudService.savedSnapshots.removeAll()
        cloudService.saveSnapshotError = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.requestRateLimited.rawValue,
            userInfo: [CKErrorRetryAfterKey: retryAfter]
        )
        let firstUploadFinished = expectation(
            description: "rate-limited upload finishes"
        )
        cloudService.saveSnapshotFinishedExpectation = firstUploadFinished

        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Retry automatically",
                body: "No new scene or push should be required.",
                happenedAt: initialDate
            ),
            importedImageData: nil
        )
        XCTAssertTrue(didSave)
        await fulfillment(of: [firstUploadFinished], timeout: 2)
        cloudService.saveSnapshotFinishedExpectation = nil

        for _ in 0..<100 {
            if !(await retrySleeper.deadlines()).isEmpty {
                break
            }
            await Task.yield()
        }
        let retryDeadline = initialDate.addingTimeInterval(retryAfter)
        let scheduledRetryDeadlines = await retrySleeper.deadlines()
        XCTAssertEqual(scheduledRetryDeadlines, [retryDeadline])
        XCTAssertEqual(scheduledBackgroundDeadlines, [retryDeadline])
        XCTAssertEqual(cloudService.savedSnapshots.count, 1)
        XCTAssertNotNil(
            try CloudUploadOutboxStore(
                repositoryRootURL: libraryStore
                    .repositoryStore(for: repositoryID)
                    .rootURL
            ).load()
        )

        cloudService.saveSnapshotError = nil
        cloudService.savedRecordChangeTag = "retry-completed"
        let retryUploadFinished = expectation(
            description: "deadline wakes exactly one upload retry"
        )
        cloudService.saveSnapshotFinishedExpectation = retryUploadFinished
        currentDate = retryDeadline
        await retrySleeper.resume()

        await fulfillment(of: [retryUploadFinished], timeout: 2)
        cloudService.saveSnapshotFinishedExpectation = nil
        for _ in 0..<100 {
            if try CloudUploadOutboxStore(
                repositoryRootURL: libraryStore
                    .repositoryStore(for: repositoryID)
                    .rootURL
            ).load() == nil {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(cloudService.savedSnapshots.count, 2)
        XCTAssertNil(
            try CloudUploadOutboxStore(
                repositoryRootURL: libraryStore
                    .repositoryStore(for: repositoryID)
                    .rootURL
            ).load()
        )
        XCTAssertNil(try libraryStore.loadPreferences().cloudRetryAfter)
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(cloudService.savedSnapshots.count, 2)
    }

    @MainActor
    func testRateLimitStopsMultiRepositoryBurstUntilDeadlineRetry() async throws {
        let rootURL = makeTempDirectory()
        let firstDescriptor = RepositoryDescriptor(
            zoneName: "throttle-first-zone",
            zoneOwnerName: "_throttle_first_owner_",
            shareRecordName: "throttle-first-share",
            role: .viewer
        )
        let secondDescriptor = RepositoryDescriptor(
            zoneName: "throttle-second-zone",
            zoneOwnerName: "_throttle_second_owner_",
            shareRecordName: "throttle-second-share",
            role: .viewer
        )
        let requestDate = fixtureDate("2026-07-24T14:00:00Z")
        var currentDate = requestDate
        let firstSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "First", happenedAt: requestDate)],
            updatedAt: requestDate
        )
        let secondSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Second", happenedAt: requestDate)],
            updatedAt: requestDate
        )
        let firstReference = RepositoryReference(
            id: firstDescriptor.storageIdentifier,
            displayName: "First Throttled Repository",
            descriptor: firstDescriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: requestDate
        )
        let secondReference = RepositoryReference(
            id: secondDescriptor.storageIdentifier,
            displayName: "Second Throttled Repository",
            descriptor: secondDescriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: requestDate
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [firstReference, secondReference],
            snapshotsByRepositoryID: [
                firstReference.id: firstSnapshot,
                secondReference.id: secondSnapshot
            ],
            preferences: AppPreferences(
                defaultRepositoryID: firstReference.id
            )
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshotsByRepositoryID = [
            firstReference.id: firstSnapshot,
            secondReference.id: secondSnapshot
        ]
        let retrySleeper = ControlledSharedCloudRetrySleeper()
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { currentDate },
            sleepUntilSharedCloudRetry: { deadline in
                await retrySleeper.sleep(until: deadline)
            }
        )
        await store.handleScenePhaseChange(.active)
        await store.loadIfNeeded()

        cloudService.loadedMetadataDescriptors.removeAll()
        cloudService.loadMetadataError = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.requestRateLimited.rawValue,
            userInfo: [CKErrorRetryAfterKey: 90]
        )

        _ = await store.refreshSharedRepositories(trigger: .manual)

        XCTAssertEqual(
            cloudService.loadedMetadataDescriptors.count,
            1,
            "The first retry-after response must stop the repository loop."
        )
        for _ in 0..<100 {
            if !(await retrySleeper.deadlines()).isEmpty {
                break
            }
            await Task.yield()
        }
        let retryDeadline = requestDate.addingTimeInterval(90)
        let deadlines = await retrySleeper.deadlines()
        XCTAssertEqual(deadlines, [retryDeadline])

        cloudService.loadMetadataError = nil
        currentDate = retryDeadline
        await retrySleeper.resume()
        for _ in 0..<200 {
            if cloudService.loadedMetadataDescriptors.count == 3 {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(
            cloudService.loadedMetadataDescriptors.count,
            3,
            "Exactly the two deferred repositories should run after expiry."
        )
    }

    @MainActor
    func testTargetedPushDoesNotSuppressForegroundCatchUpForLaterChanges() async throws {
        let rootURL = makeTempDirectory()
        let descriptor = RepositoryDescriptor(
            zoneName: "targeted-then-foreground-zone",
            zoneOwnerName: "_targeted_then_foreground_owner_",
            shareRecordName: "targeted-then-foreground-share",
            role: .viewer
        )
        let repositoryID = descriptor.storageIdentifier
        let initialDate = fixtureDate("2026-07-22T09:00:00Z")
        let pushedDate = fixtureDate("2026-07-22T09:00:31Z")
        let foregroundDate = fixtureDate("2026-07-22T09:00:32Z")
        let initialSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Initial", happenedAt: initialDate)],
            updatedAt: initialDate
        )
        let pushedSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "From push", happenedAt: pushedDate)],
            updatedAt: pushedDate
        )
        let foregroundSnapshot = RepositorySnapshot(
            entries: [makeEntry(title: "Caught on foreground", happenedAt: foregroundDate)],
            updatedAt: foregroundDate
        )
        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Targeted Then Foreground",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: initialDate,
            lastKnownServerRecordChangeTag: "initial-tag"
        )
        let libraryStore = try makeCloudBackedLibrary(
            rootURL: rootURL,
            references: [reference],
            snapshotsByRepositoryID: [repositoryID: initialSnapshot],
            preferences: AppPreferences(defaultRepositoryID: repositoryID)
        )
        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = initialSnapshot
        cloudService.metadataRecordChangeTag = "initial-tag"
        var currentDate = initialDate
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { currentDate }
        )

        await store.loadIfNeeded()
        XCTAssertEqual(cloudService.loadedMetadataDescriptors.count, 1)
        XCTAssertTrue(cloudService.loadedDescriptors.isEmpty)

        currentDate = pushedDate
        cloudService.loadedSnapshot = pushedSnapshot
        cloudService.metadataRecordChangeTag = "pushed-tag"
        _ = await store.handleRemoteRepositoryChange(
            .zone(
                ownerName: "_targeted_then_foreground_owner_",
                zoneName: "targeted-then-foreground-zone"
            ),
            trigger: .push
        )
        XCTAssertEqual(store.entries.first?.title, "From push")

        currentDate = foregroundDate
        cloudService.loadedSnapshot = foregroundSnapshot
        cloudService.metadataRecordChangeTag = "foreground-tag"
        await store.handleScenePhaseChange(.active)

        XCTAssertEqual(cloudService.loadedMetadataDescriptors.count, 3)
        XCTAssertEqual(cloudService.loadedDescriptors.count, 2)
        XCTAssertEqual(store.entries.first?.title, "Caught on foreground")
    }

    @MainActor
    func testRemoteChangeCenterAwaitsRecoveryHandlerAndRejectsNonCloudKitPayload() async {
        let center = RepositoryRemoteChangeCenter()
        let probe = RemoteChangeHandlerProbe()
        center.installHandler { target in
            try? await Task.sleep(nanoseconds: 20_000_000)
            await probe.record(target: target)
            return .newData
        }

        let recoveryResult = await center.performRecoveryRefresh()
        let stateAfterRecovery = await probe.state()

        XCTAssertEqual(recoveryResult.rawValue, UIBackgroundFetchResult.newData.rawValue)
        XCTAssertEqual(stateAfterRecovery.callCount, 1)
        XCTAssertTrue(stateAfterRecovery.receivedNilTarget)

        let nonCloudKitResult = await center.processRemoteNotification([
            "aps": ["content-available": 1]
        ])
        let stateAfterInvalidPayload = await probe.state()

        XCTAssertEqual(nonCloudKitResult.rawValue, UIBackgroundFetchResult.noData.rawValue)
        XCTAssertEqual(stateAfterInvalidPayload.callCount, 1)
    }

    private func makeCloudBackedLibrary(
        rootURL: URL,
        references: [RepositoryReference],
        snapshotsByRepositoryID: [String: RepositorySnapshot],
        preferences: AppPreferences
    ) throws -> RepositoryLibraryStore {
        let libraryStore = RepositoryLibraryStore(rootURL: rootURL)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let localSnapshot = RepositorySnapshot(
            entries: [],
            updatedAt: fixtureDate("2026-07-19T09:00:00Z")
        )
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(localSnapshot)

        for reference in references {
            let repositoryStore = libraryStore.repositoryStore(for: reference.id)
            try repositoryStore.saveDescriptor(reference.descriptor)
            if let snapshot = snapshotsByRepositoryID[reference.id] {
                try repositoryStore.saveSnapshot(snapshot)
            }
        }

        try libraryStore.saveCatalog([RepositoryReference.local] + references)
        try libraryStore.savePreferences(preferences)
        return libraryStore
    }
}

private enum SimulatedUploadError: Error {
    case failed
}

private enum SimulatedSubscriptionRepairError: Error {
    case failed
}

private enum SimulatedDownloadError: Error {
    case failed
}

private enum SimulatedAccountLookupError: Error {
    case failed
}

private actor RemoteChangeHandlerProbe {
    private var callCount = 0
    private var receivedNilTarget = false

    func record(target: CloudRemoteNotificationTarget?) {
        callCount += 1
        receivedNilTarget = target == nil
    }

    func state() -> (callCount: Int, receivedNilTarget: Bool) {
        (callCount, receivedNilTarget)
    }
}

private actor ControlledSharedCloudRetrySleeper {
    private var scheduledDeadlines: [Date] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func sleep(until deadline: Date) async {
        scheduledDeadlines.append(deadline)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func deadlines() -> [Date] {
        scheduledDeadlines
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
