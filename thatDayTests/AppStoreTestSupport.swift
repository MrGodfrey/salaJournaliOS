import CloudKit
import ObjectiveC.runtime
import UIKit
import XCTest
@testable import thatDay

class AppStoreTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("THATDAY_APP_LANGUAGE", "en", 1)
    }

    override func tearDown() {
        unsetenv("THATDAY_APP_LANGUAGE")
        super.tearDown()
    }

    @MainActor
    func makeStore(
        now: Date,
        entries: [EntryRecord]? = nil,
        blogTags: [String] = RepositorySnapshot.defaultBlogTags,
        rootURL: URL? = nil,
        cloudService: any CloudRepositoryServicing = MockCloudRepositoryService(),
        preferences: AppPreferences? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        authenticateBiometrics: @escaping (String) async throws -> Void = { _ in },
        setApplicationBadgeCount: @escaping (Int) -> Void = { _ in }
    ) throws -> AppStore {
        let libraryRoot = rootURL ?? makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: libraryRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)

        try localStore.saveDescriptor(.local)
        if let entries {
            try localStore.saveSnapshot(
                RepositorySnapshot(
                    entries: entries,
                    updatedAt: now,
                    blogTags: blogTags
                )
            )
        }
        if let preferences {
            try libraryStore.savePreferences(preferences)
        }

        return AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            calendar: calendar,
            now: { now },
            authenticateBiometrics: authenticateBiometrics,
            setApplicationBadgeCount: setApplicationBadgeCount
        )
    }

    func makeEntry(
        kind: EntryKind = .journal,
        title: String,
        body: String = "Body",
        blogTag: String? = nil,
        blogImageLayout: BlogCardImageLayout = .landscape,
        happenedAt: Date
    ) -> EntryRecord {
        EntryRecord(
            kind: kind,
            title: title,
            body: body,
            blogTag: blogTag,
            blogImageLayout: blogImageLayout,
            happenedAt: happenedAt,
            createdAt: happenedAt,
            updatedAt: happenedAt
        )
    }

    func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeSymlinkedTempDirectory() throws -> URL {
        let containerURL = makeTempDirectory()
        let targetURL = containerURL.appendingPathComponent("real-root", isDirectory: true)
        let symlinkURL = containerURL.appendingPathComponent("tmp", isDirectory: true)

        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

        return symlinkURL
    }

    func makePreviewImageData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200))
        let image = renderer.image { context in
            context.cgContext.setFillColor(UIColor.systemIndigo.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(x: 24, y: 24, width: 272, height: 152))
        }
        return image.pngData()
    }

    func makeLargeImageData() -> Data? {
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

    func fixtureDate(_ rawValue: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue) ?? .now
    }

    func words(_ count: Int) -> String {
        Array(repeating: "word", count: count).joined(separator: " ")
    }

    func makeShareMetadata() throws -> CKShare.Metadata {
        let instance = try XCTUnwrap(class_createInstance(CKShare.Metadata.self, 0)) as AnyObject
        return unsafeDowncast(instance, to: CKShare.Metadata.self)
    }
}

final class MockCloudRepositoryService: CloudRepositoryServicing {
    var requiresExplicitAccountIdentityMigrationConfirmation =
        false
    var loadedSnapshot: RepositorySnapshot?
    var loadedSnapshotsByRepositoryID: [String: RepositorySnapshot] = [:]
    var acceptedSharedRepository: AcceptedSharedRepository?
    var loadMetadataError: Error?
    var loadSnapshotError: Error?
    var saveSnapshotError: Error?
    var saveSnapshotErrors: [Error] = []
    var recreateSnapshotError: Error?
    var ensureSubscriptionError: Error?
    var ensureSubscriptionErrorsByRole: [RepositoryRole: Error] = [:]
    var acknowledgeZoneChangesError: Error?
    var makeSharingControllerError: Error?
    var metadataRecordChangeTag: String?
    var metadataServerModifiedAt: Date?
    var savedRecordChangeTag: String?
    var loadedSnapshotEnvelope: LoadedRepositorySnapshot?
    var loadedSnapshotEnvelopes: [LoadedRepositorySnapshot] = []
    var accountAvailability: CloudAccountAvailability =
        .available(userRecordName: "mock-cloud-account")
    var accountAvailabilityError: Error?
    var recreateSnapshotResult: SavedRepositorySnapshot?
    var savedSnapshots: [RepositorySnapshot] = []
    var savedDescriptors: [RepositoryDescriptor] = []
    var savedExpectedRecordChangeTags: [String?] = []
    var savedAcceptedPredecessorOperationIDs: [Set<UUID>] = []
    var recreatedSnapshots: [RepositorySnapshot] = []
    var recreatedDescriptors: [RepositoryDescriptor] = []
    var recreatedAcceptedPredecessorOperationIDs: [Set<UUID>] = []
    var sharingControllerDescriptors: [RepositoryDescriptor] = []
    var sharingControllerSnapshots: [RepositorySnapshot] = []
    var loadedMetadataDescriptors: [RepositoryDescriptor] = []
    var loadedDescriptors: [RepositoryDescriptor] = []
    var availableImageContentHashesByLoad: [[String: String]] = []
    var ensuredSubscriptionDescriptors: [RepositoryDescriptor] = []
    var changedZoneIDsByScope: [CloudDatabaseScope: Set<CloudRepositoryZoneIdentity>] = [:]
    var deletedZonesByScope: [CloudDatabaseScope: Set<CloudRepositoryZoneDeletion>] = [:]
    var deletedZoneIDsByScope: [CloudDatabaseScope: Set<CloudRepositoryZoneIdentity>] = [:]
    var changedZoneScopeRequests: [CloudDatabaseScope] = []
    var acknowledgedZoneIDsByScope: [CloudDatabaseScope: [Set<CloudRepositoryZoneIdentity>]] = [:]
    var acknowledgedDeletedZonesByScope: [CloudDatabaseScope: [Set<CloudRepositoryZoneDeletion>]] = [:]
    var acknowledgedDeletedZoneIDsByScope: [CloudDatabaseScope: [Set<CloudRepositoryZoneIdentity>]] = [:]
    var resetRemoteChangeTrackingCount = 0
    var acceptedShareURLs: [URL] = []
    var acceptedShareMetadataCount = 0
    var accountAvailabilityRequestCount = 0
    var loadMetadataStartedExpectation: XCTestExpectation?
    var loadSnapshotEnvelopeStartedExpectation: XCTestExpectation?
    var accountAvailabilityStartedExpectation: XCTestExpectation?
    var acceptShareStartedExpectation: XCTestExpectation?
    var resetRemoteChangeTrackingStartedExpectation:
        XCTestExpectation?
    var saveSnapshotStartedExpectation: XCTestExpectation?
    var saveSnapshotFinishedExpectation: XCTestExpectation?
    var recreateSnapshotStartedExpectation: XCTestExpectation?
    var recreateSnapshotFinishedExpectation: XCTestExpectation?
    var pauseLoadMetadata = false
    var pauseLoadSnapshotEnvelope = false
    var pauseAccountAvailability = false
    var pauseAcceptShare = false
    var pauseResetRemoteChangeTracking = false
    var pauseSaveSnapshot = false
    var pauseRecreateSnapshot = false

    private var loadMetadataContinuation: CheckedContinuation<Void, Never>?
    private var loadSnapshotEnvelopeContinuation:
        CheckedContinuation<Void, Never>?
    private var accountAvailabilityContinuation:
        CheckedContinuation<Void, Never>?
    private var acceptShareContinuation:
        CheckedContinuation<Void, Never>?
    private var resetRemoteChangeTrackingContinuation:
        CheckedContinuation<Void, Never>?
    private var saveSnapshotContinuation: CheckedContinuation<Void, Never>?
    private var recreateSnapshotContinuation: CheckedContinuation<Void, Never>?

    func loadSnapshotMetadata(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshotMetadata {
        loadedMetadataDescriptors.append(descriptor)

        if pauseLoadMetadata, loadMetadataContinuation == nil {
            await withCheckedContinuation { continuation in
                loadMetadataContinuation = continuation
                loadMetadataStartedExpectation?.fulfill()
            }
        } else {
            loadMetadataStartedExpectation?.fulfill()
        }

        if let loadMetadataError {
            throw loadMetadataError
        }

        if let loadedSnapshot = snapshot(for: descriptor) {
            return RepositorySnapshotMetadata(
                updatedAt: loadedSnapshot.updatedAt,
                entryCount: loadedSnapshot.entries.count,
                serverModifiedAt: metadataServerModifiedAt,
                recordChangeTag: metadataRecordChangeTag
            )
        }

        throw CloudRepositoryError.repositoryNotFound
    }

    func resumePausedLoadMetadata() {
        loadMetadataContinuation?.resume()
        loadMetadataContinuation = nil
        pauseLoadMetadata = false
    }

    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot {
        loadedDescriptors.append(descriptor)

        if let loadSnapshotError {
            throw loadSnapshotError
        }

        if let loadedSnapshot = snapshot(for: descriptor) {
            return loadedSnapshot
        }

        throw CloudRepositoryError.repositoryNotFound
    }

    func loadSnapshot(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String]
    ) async throws -> RepositorySnapshot {
        availableImageContentHashesByLoad.append(
            availableImageContentHashes
        )
        return try await loadSnapshot(using: descriptor)
    }

    func loadSnapshotWithMetadata(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String]
    ) async throws -> LoadedRepositorySnapshot {
        availableImageContentHashesByLoad.append(
            availableImageContentHashes
        )
        loadedDescriptors.append(descriptor)
        loadedMetadataDescriptors.append(descriptor)
        if pauseLoadSnapshotEnvelope,
           loadSnapshotEnvelopeContinuation == nil {
            await withCheckedContinuation { continuation in
                loadSnapshotEnvelopeContinuation = continuation
                loadSnapshotEnvelopeStartedExpectation?.fulfill()
            }
        } else {
            loadSnapshotEnvelopeStartedExpectation?.fulfill()
        }
        if let loadSnapshotError {
            throw loadSnapshotError
        }
        if let loadMetadataError {
            throw loadMetadataError
        }
        if !loadedSnapshotEnvelopes.isEmpty {
            return loadedSnapshotEnvelopes.removeFirst()
        }
        if let loadedSnapshotEnvelope {
            return loadedSnapshotEnvelope
        }
        guard let loadedSnapshot = snapshot(for: descriptor) else {
            throw CloudRepositoryError.repositoryNotFound
        }
        return LoadedRepositorySnapshot(
            snapshot: loadedSnapshot,
            metadata: RepositorySnapshotMetadata(
                updatedAt: loadedSnapshot.updatedAt,
                entryCount: loadedSnapshot.entries.count,
                serverModifiedAt: metadataServerModifiedAt,
                recordChangeTag: metadataRecordChangeTag
            )
        )
    }

    func resumePausedLoadSnapshotEnvelope() {
        loadSnapshotEnvelopeContinuation?.resume()
        loadSnapshotEnvelopeContinuation = nil
        pauseLoadSnapshotEnvelope = false
    }

    func saveSnapshot(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        expectedRecordChangeTag: String?,
        acceptedPredecessorOperationIDs: Set<UUID>
    ) async throws -> SavedRepositorySnapshot {
        savedSnapshots.append(snapshot)
        savedDescriptors.append(descriptor)
        savedExpectedRecordChangeTags.append(expectedRecordChangeTag)
        savedAcceptedPredecessorOperationIDs.append(
            acceptedPredecessorOperationIDs
        )

        if pauseSaveSnapshot {
            await withCheckedContinuation { continuation in
                saveSnapshotContinuation = continuation
                saveSnapshotStartedExpectation?.fulfill()
            }
        } else {
            saveSnapshotStartedExpectation?.fulfill()
        }

        if !saveSnapshotErrors.isEmpty {
            let error = saveSnapshotErrors.removeFirst()
            saveSnapshotFinishedExpectation?.fulfill()
            throw error
        }
        if let saveSnapshotError {
            saveSnapshotFinishedExpectation?.fulfill()
            throw saveSnapshotError
        }

        if descriptor.role == .local {
            saveSnapshotFinishedExpectation?.fulfill()
            return SavedRepositorySnapshot(
                descriptor: RepositoryDescriptor(
                    zoneName: "mock-zone",
                    zoneOwnerName: CKCurrentUserDefaultName,
                    shareRecordName: "mock-share",
                    role: .owner
                ),
                serverModifiedAt: metadataServerModifiedAt,
                recordChangeTag: savedRecordChangeTag ??
                    metadataRecordChangeTag ??
                    "mock-save-\(savedSnapshots.count)"
            )
        }

        saveSnapshotFinishedExpectation?.fulfill()
        return SavedRepositorySnapshot(
            descriptor: descriptor,
            serverModifiedAt: metadataServerModifiedAt,
            recordChangeTag: savedRecordChangeTag ??
                metadataRecordChangeTag ??
                "mock-save-\(savedSnapshots.count)"
        )
    }

    func recreateSnapshotAfterEncryptedDataReset(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        acceptedPredecessorOperationIDs: Set<UUID>
    ) async throws -> SavedRepositorySnapshot {
        recreatedSnapshots.append(snapshot)
        recreatedDescriptors.append(descriptor)
        recreatedAcceptedPredecessorOperationIDs.append(
            acceptedPredecessorOperationIDs
        )

        if pauseRecreateSnapshot {
            await withCheckedContinuation { continuation in
                recreateSnapshotContinuation = continuation
                recreateSnapshotStartedExpectation?.fulfill()
            }
        } else {
            recreateSnapshotStartedExpectation?.fulfill()
        }

        if let recreateSnapshotError {
            recreateSnapshotFinishedExpectation?.fulfill()
            throw recreateSnapshotError
        }

        let result = recreateSnapshotResult ?? SavedRepositorySnapshot(
            descriptor: descriptor,
            serverModifiedAt: metadataServerModifiedAt,
            recordChangeTag: savedRecordChangeTag ??
                metadataRecordChangeTag ??
                "mock-recreate-\(recreatedSnapshots.count)"
        )
        recreateSnapshotFinishedExpectation?.fulfill()
        return result
    }

    func resumePausedRecreateSnapshot() {
        recreateSnapshotContinuation?.resume()
        recreateSnapshotContinuation = nil
        pauseRecreateSnapshot = false
    }

    func resumePausedSaveSnapshot() {
        saveSnapshotContinuation?.resume()
        saveSnapshotContinuation = nil
        pauseSaveSnapshot = false
    }

    func ensureRepositorySubscription(using descriptor: RepositoryDescriptor) async throws {
        ensuredSubscriptionDescriptors.append(descriptor)
        if let roleError = ensureSubscriptionErrorsByRole[descriptor.role] {
            throw roleError
        }
        if let ensureSubscriptionError {
            throw ensureSubscriptionError
        }
    }

    func cloudAccountAvailability() async throws
        -> CloudAccountAvailability {
        accountAvailabilityRequestCount += 1
        if pauseAccountAvailability,
           accountAvailabilityContinuation == nil {
            await withCheckedContinuation { continuation in
                accountAvailabilityContinuation = continuation
                accountAvailabilityStartedExpectation?.fulfill()
            }
        } else {
            accountAvailabilityStartedExpectation?.fulfill()
        }
        if let accountAvailabilityError {
            throw accountAvailabilityError
        }
        return accountAvailability
    }

    func resumePausedAccountAvailability() {
        accountAvailabilityContinuation?.resume()
        accountAvailabilityContinuation = nil
        pauseAccountAvailability = false
    }

    func pendingRepositoryZoneChanges(
        in scope: CloudDatabaseScope
    ) async throws -> CloudRepositoryDatabaseChanges {
        changedZoneScopeRequests.append(scope)
        let legacyDeletedZones = Set(
            (deletedZoneIDsByScope[scope] ?? []).map {
                CloudRepositoryZoneDeletion(zoneID: $0, reason: .deleted)
            }
        )
        return CloudRepositoryDatabaseChanges(
            modifiedZoneIDs: changedZoneIDsByScope[scope] ?? [],
            deletedZones: (deletedZonesByScope[scope] ?? []).union(legacyDeletedZones)
        )
    }

    func acknowledgeRepositoryZoneChanges(
        _ changes: CloudRepositoryDatabaseChanges,
        in scope: CloudDatabaseScope
    ) async throws {
        acknowledgedZoneIDsByScope[scope, default: []].append(changes.modifiedZoneIDs)
        acknowledgedDeletedZonesByScope[scope, default: []].append(changes.deletedZones)
        let deletedZoneIDs = Set(changes.deletedZones.map(\.zoneID))
        acknowledgedDeletedZoneIDsByScope[scope, default: []].append(deletedZoneIDs)

        if let acknowledgeZoneChangesError {
            throw acknowledgeZoneChangesError
        }

        changedZoneIDsByScope[scope]?.subtract(changes.modifiedZoneIDs)
        deletedZonesByScope[scope]?.subtract(changes.deletedZones)
        deletedZoneIDsByScope[scope]?.subtract(deletedZoneIDs)
    }

    func resetRemoteChangeTracking() async throws {
        resetRemoteChangeTrackingCount += 1
        if pauseResetRemoteChangeTracking,
           resetRemoteChangeTrackingContinuation == nil {
            await withCheckedContinuation { continuation in
                resetRemoteChangeTrackingContinuation =
                    continuation
                resetRemoteChangeTrackingStartedExpectation?
                    .fulfill()
            }
        } else {
            resetRemoteChangeTrackingStartedExpectation?.fulfill()
        }
    }

    func resumePausedResetRemoteChangeTracking() {
        resetRemoteChangeTrackingContinuation?.resume()
        resetRemoteChangeTrackingContinuation = nil
        pauseResetRemoteChangeTracking = false
    }

    @MainActor
    func makeSharingController(
        using descriptor: RepositoryDescriptor,
        snapshot: RepositorySnapshot,
        access: ShareAccessOption
    ) async throws -> UICloudSharingController {
        sharingControllerDescriptors.append(descriptor)
        sharingControllerSnapshots.append(snapshot)

        if let makeSharingControllerError {
            throw makeSharingControllerError
        }

        return UICloudSharingController(
            share: CKShare(recordZoneID: CKRecordZone.ID(zoneName: "mock-zone", ownerName: CKCurrentUserDefaultName)),
            container: CKContainer(identifier: "iCloud.yu.thatDay")
        )
    }

    func acceptShare(from url: URL) async throws -> AcceptedSharedRepository {
        acceptedShareURLs.append(url)

        if pauseAcceptShare,
           acceptShareContinuation == nil {
            await withCheckedContinuation { continuation in
                acceptShareContinuation = continuation
                acceptShareStartedExpectation?.fulfill()
            }
        } else {
            acceptShareStartedExpectation?.fulfill()
        }
        if let acceptedSharedRepository {
            return acceptedSharedRepository
        }

        throw CloudRepositoryError.shareLinkInvalid
    }

    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository {
        acceptedShareMetadataCount += 1

        if pauseAcceptShare,
           acceptShareContinuation == nil {
            await withCheckedContinuation { continuation in
                acceptShareContinuation = continuation
                acceptShareStartedExpectation?.fulfill()
            }
        } else {
            acceptShareStartedExpectation?.fulfill()
        }
        if let acceptedSharedRepository {
            return acceptedSharedRepository
        }

        throw CloudRepositoryError.shareLinkInvalid
    }

    func resumePausedAcceptShare() {
        acceptShareContinuation?.resume()
        acceptShareContinuation = nil
        pauseAcceptShare = false
    }

    private func snapshot(for descriptor: RepositoryDescriptor) -> RepositorySnapshot? {
        loadedSnapshotsByRepositoryID[descriptor.storageIdentifier] ?? loadedSnapshot
    }
}

final class MockBiometricAuthenticator {
    private(set) var reasons: [String] = []
    var results: [Result<Void, Error>] = []

    func authenticate(reason: String) async throws {
        reasons.append(reason)

        guard !results.isEmpty else {
            return
        }

        switch results.removeFirst() {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}
