import CloudKit
import CryptoKit
import Foundation
import UIKit

nonisolated struct RepositorySnapshotMetadata: Equatable, Sendable {
    var updatedAt: Date
    var entryCount: Int
    var serverModifiedAt: Date? = nil
    var recordChangeTag: String? = nil
}

nonisolated struct SavedRepositorySnapshot: Equatable, Sendable {
    var descriptor: RepositoryDescriptor
    var serverModifiedAt: Date?
    var recordChangeTag: String?
}

nonisolated struct CloudImageMutationPlan: Equatable, Sendable {
    var assetsToSave: [RepositoryImageAsset]
    var referencesToInspectBeforeSave: [String]
    var referencesToDelete: [String]
}

nonisolated struct CloudRepositoryZoneIdentity: Codable, Hashable, Sendable {
    var ownerName: String
    var zoneName: String

    init(ownerName: String, zoneName: String) {
        self.ownerName = ownerName
        self.zoneName = zoneName
    }

    init(zoneID: CKRecordZone.ID) {
        self.init(ownerName: zoneID.ownerName, zoneName: zoneID.zoneName)
    }
}

nonisolated enum CloudRepositoryZoneDeletionReason: String, Codable, Hashable, Sendable {
    case deleted
    case purged
    case encryptedDataReset
}

nonisolated struct CloudRepositoryZoneDeletion: Codable, Hashable, Sendable {
    var zoneID: CloudRepositoryZoneIdentity
    var reason: CloudRepositoryZoneDeletionReason
}

nonisolated struct CloudRepositoryDatabaseChanges: Equatable, Sendable {
    var modifiedZoneIDs: Set<CloudRepositoryZoneIdentity> = []
    var deletedZones: Set<CloudRepositoryZoneDeletion> = []
}

protocol CloudRepositoryServicing {
    func loadSnapshotMetadata(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshotMetadata
    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot
    func loadSnapshot(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String]
    ) async throws -> RepositorySnapshot
    func saveSnapshot(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        expectedRecordChangeTag: String?,
        acceptedPredecessorOperationIDs: Set<UUID>
    ) async throws -> SavedRepositorySnapshot
    func recreateSnapshotAfterEncryptedDataReset(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        acceptedPredecessorOperationIDs: Set<UUID>
    ) async throws -> SavedRepositorySnapshot
    func ensureRepositorySubscription(using descriptor: RepositoryDescriptor) async throws
    func pendingRepositoryZoneChanges(
        in scope: CloudDatabaseScope
    ) async throws -> CloudRepositoryDatabaseChanges
    func acknowledgeRepositoryZoneChanges(
        _ changes: CloudRepositoryDatabaseChanges,
        in scope: CloudDatabaseScope
    ) async throws
    func resetRemoteChangeTracking() async throws
    @MainActor
    func makeSharingController(
        using descriptor: RepositoryDescriptor,
        snapshot: RepositorySnapshot,
        access: ShareAccessOption
    ) async throws -> UICloudSharingController
    func acceptShare(from url: URL) async throws -> AcceptedSharedRepository
    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository
}

extension CloudRepositoryServicing {
    func loadSnapshot(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String]
    ) async throws -> RepositorySnapshot {
        try await loadSnapshot(using: descriptor)
    }
}

struct AcceptedSharedRepository: Sendable {
    var descriptor: RepositoryDescriptor
    var snapshot: RepositorySnapshot
    var displayName: String?
    var serverModifiedAt: Date?
    var recordChangeTag: String?

    init(
        descriptor: RepositoryDescriptor,
        snapshot: RepositorySnapshot,
        displayName: String?,
        serverModifiedAt: Date? = nil,
        recordChangeTag: String? = nil
    ) {
        self.descriptor = descriptor
        self.snapshot = snapshot
        self.displayName = displayName
        self.serverModifiedAt = serverModifiedAt
        self.recordChangeTag = recordChangeTag
    }
}

enum CloudRepositoryError: LocalizedError {
    case repositoryDescriptorMissing
    case shareLinkInvalid
    case repositoryNotFound
    case repositoryLocked
    case repositoryConflict(serverRecordChangeTag: String?)
    case atomicSaveLimitExceeded
    case invalidRepositoryData
    case shareUnavailable

    var errorDescription: String? {
        switch self {
        case .repositoryDescriptorMissing:
            L10n.string("The current repository is not connected to CloudKit yet.")
        case .shareLinkInvalid:
            L10n.string("Enter a valid iCloud share link.")
        case .repositoryNotFound:
            L10n.string("No data was found for the current shared repository.")
        case .repositoryLocked:
            L10n.string("The current shared repository is read-only and cannot be changed.")
        case .repositoryConflict:
            L10n.string("This repository changed in iCloud before the pending local update could upload. Both copies were kept; automatic upload is paused to prevent data loss.")
        case .atomicSaveLimitExceeded:
            L10n.string("The repository update is too large to upload safely in one atomic CloudKit operation.")
        case .invalidRepositoryData:
            L10n.string("The repository data in CloudKit could not be recognized.")
        case .shareUnavailable:
            L10n.string("A share invite cannot be created right now. Confirm that iCloud and CloudKit are configured.")
        }
    }
}

final class CloudRepositoryService: CloudRepositoryServicing {
    private enum Constant {
        static let zoneName = "thatday-repository"
        static let rootRecordName = "RepositoryRoot"
        static let recordType = "RepositoryRoot"
        static let imageRecordType = "RepositoryImageAsset"
        static let privateDatabaseSubscriptionID = "repository-root-updates-private-v2"
        static let sharedDatabaseSubscriptionID = "repository-root-updates-shared-v2"
        static let legacySharedDatabaseSubscriptionID = "repository-updates-shared-database"
        static let updatedAtKey: CKRecord.FieldKey = "updatedAt"
        static let entryCountKey: CKRecord.FieldKey = "entryCount"
        static let payloadKey: CKRecord.FieldKey = "payload"
        static let referenceKey: CKRecord.FieldKey = "reference"
        static let contentHashKey: CKRecord.FieldKey = "contentHash"
        static let recordBatchSize = 50
        static let maximumAtomicRecordsPerSave = 400
    }

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase
    private let changeTokenStore: CloudChangeTokenStore?

    init(containerIdentifier: String, changeTokenStoreURL: URL? = nil) {
        container = CKContainer(identifier: containerIdentifier)
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
        if let changeTokenStoreURL {
            changeTokenStore = CloudChangeTokenStore(directoryURL: changeTokenStoreURL)
        } else {
            changeTokenStore = nil
        }
    }

    nonisolated static func imageMutationPlan(
        for snapshot: RepositorySnapshot,
        replacing previousSnapshot: RepositorySnapshot?
    ) throws -> CloudImageMutationPlan {
        let currentReferences = localImageReferences(in: snapshot)
        let previousReferences = previousSnapshot.map {
            localImageReferences(in: $0)
        } ?? []
        let assetsByReference = Dictionary(
            snapshot.embeddedImages.compactMap { asset -> (String, RepositoryImageAsset)? in
                guard let reference = localImageReference(asset.reference) else {
                    return nil
                }
                return (
                    reference,
                    RepositoryImageAsset(reference: reference, data: asset.data)
                )
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let currentContentHashes = try imageContentHashes(in: snapshot)
        let referencesToSave = Set(
            currentReferences.filter { reference in
                guard previousReferences.contains(reference) else {
                    return true
                }
                return previousSnapshot?.imageContentHashes[reference] !=
                    currentContentHashes[reference]
            }
        )
        guard referencesToSave.isSubset(of: Set(assetsByReference.keys)) else {
            throw CloudRepositoryError.invalidRepositoryData
        }

        return CloudImageMutationPlan(
            assetsToSave: referencesToSave
                .sorted()
                .compactMap { assetsByReference[$0] },
            // Inspect every candidate, including a root-new reference. Older
            // app versions could leave an orphan image record with the same
            // deterministic ID after removing it from the root snapshot.
            referencesToInspectBeforeSave: referencesToSave.sorted(),
            referencesToDelete: previousReferences
                .subtracting(currentReferences)
                .sorted()
        )
    }

    nonisolated static func imageReferencesRequiringDownload(
        in snapshot: RepositorySnapshot,
        availableImageContentHashes: [String: String]
    ) -> Set<String> {
        let referencedImages = localImageReferences(in: snapshot)
        let embeddedReferences = Set(
            snapshot.embeddedImages.compactMap {
                localImageReference($0.reference)
            }
        )
        let reusableReferences = referencedImages.filter { reference in
            guard let remoteHash = snapshot.imageContentHashes[reference],
                  let localHash = availableImageContentHashes[reference] else {
                return false
            }
            return remoteHash == localHash
        }
        return referencedImages
            .subtracting(embeddedReferences)
            .subtracting(reusableReferences)
    }

    nonisolated static func imageContentHashes(
        in snapshot: RepositorySnapshot
    ) throws -> [String: String] {
        let referencedImages = localImageReferences(in: snapshot)
        let hashesByReference = Dictionary(
            snapshot.embeddedImages.compactMap { asset -> (String, String)? in
                guard let reference = localImageReference(asset.reference) else {
                    return nil
                }
                return (reference, contentHash(for: asset.data))
            },
            uniquingKeysWith: { _, latest in latest }
        )
        guard referencedImages.isSubset(of: Set(hashesByReference.keys)) else {
            throw CloudRepositoryError.invalidRepositoryData
        }
        return hashesByReference.filter {
            referencedImages.contains($0.key)
        }
    }

    nonisolated static func validatedImageAsset(
        requestedReference: String,
        storedReference: String?,
        recordedContentHash: String?,
        expectedContentHash: String?,
        data: Data
    ) throws -> RepositoryImageAsset {
        let normalizedStoredReference =
            localImageReference(storedReference) ?? requestedReference
        let actualContentHash = contentHash(for: data)
        guard normalizedStoredReference == requestedReference,
              recordedContentHash.map({ $0 == actualContentHash }) ?? true,
              expectedContentHash.map({ $0 == actualContentHash }) ?? true else {
            throw CloudRepositoryError.invalidRepositoryData
        }
        return RepositoryImageAsset(
            reference: requestedReference,
            data: data
        )
    }

    func loadSnapshotMetadata(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshotMetadata {
        guard let zoneID = descriptor.zoneID else {
            throw CloudRepositoryError.repositoryDescriptorMissing
        }

        let database = database(for: descriptor.role)
        let recordID = CKRecord.ID(recordName: Constant.rootRecordName, zoneID: zoneID)
        guard let record = try await fetchRecordIfPresent(
            recordID: recordID,
            in: database,
            desiredKeys: [Constant.updatedAtKey, Constant.entryCountKey]
        ) else {
            throw CloudRepositoryError.repositoryNotFound
        }

        guard let updatedAt = record[Constant.updatedAtKey] as? Date else {
            throw CloudRepositoryError.invalidRepositoryData
        }

        let entryCount = record[Constant.entryCountKey] as? Int ?? 0
        return RepositorySnapshotMetadata(
            updatedAt: updatedAt,
            entryCount: entryCount,
            serverModifiedAt: record.modificationDate,
            recordChangeTag: record.recordChangeTag
        )
    }

    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot {
        try await loadSnapshotWithMetadata(
            using: descriptor,
            availableImageContentHashes: [:]
        ).snapshot
    }

    func loadSnapshot(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String]
    ) async throws -> RepositorySnapshot {
        try await loadSnapshotWithMetadata(
            using: descriptor,
            availableImageContentHashes: availableImageContentHashes
        ).snapshot
    }

    private func loadSnapshotWithMetadata(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String] = [:]
    ) async throws -> (
        snapshot: RepositorySnapshot,
        metadata: RepositorySnapshotMetadata
    ) {
        guard let zoneID = descriptor.zoneID else {
            throw CloudRepositoryError.repositoryDescriptorMissing
        }

        let database = database(for: descriptor.role)
        let recordID = CKRecord.ID(recordName: Constant.rootRecordName, zoneID: zoneID)
        guard let record = try await fetchRecordIfPresent(recordID: recordID, in: database) else {
            throw CloudRepositoryError.repositoryNotFound
        }

        guard let asset = record[Constant.payloadKey] as? CKAsset,
              let data = try Self.assetData(from: asset) else {
            throw CloudRepositoryError.invalidRepositoryData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(RepositorySnapshot.self, from: data)
        let missingReferences = Self.imageReferencesRequiringDownload(
            in: snapshot,
            availableImageContentHashes: availableImageContentHashes
        )
        let fetchedImages: [RepositoryImageAsset]
        if missingReferences.isEmpty {
            fetchedImages = []
        } else {
            fetchedImages = try await fetchImageAssets(
                references: Array(missingReferences).sorted(),
                expectedContentHashes: snapshot.imageContentHashes,
                zoneID: zoneID,
                in: database
            )
        }
        var hydratedImageContentHashes = snapshot.imageContentHashes
        for asset in fetchedImages {
            hydratedImageContentHashes[asset.reference] =
                Self.contentHash(for: asset.data)
        }

        let hydratedSnapshot = RepositorySnapshot(
            entries: snapshot.entries,
            updatedAt: snapshot.updatedAt,
            embeddedImages: snapshot.embeddedImages + fetchedImages,
            blogTags: snapshot.blogTags,
            sharedUpdateNotificationScope: snapshot.sharedUpdateNotificationScope,
            cloudUploadOperationID: snapshot.cloudUploadOperationID,
            imageContentHashes: hydratedImageContentHashes
        )
        let metadata = RepositorySnapshotMetadata(
            updatedAt: (record[Constant.updatedAtKey] as? Date) ?? snapshot.updatedAt,
            entryCount: record[Constant.entryCountKey] as? Int ?? snapshot.entries.count,
            serverModifiedAt: record.modificationDate,
            recordChangeTag: record.recordChangeTag
        )
        return (hydratedSnapshot, metadata)
    }

    func saveSnapshot(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        expectedRecordChangeTag: String?,
        acceptedPredecessorOperationIDs: Set<UUID> = []
    ) async throws -> SavedRepositorySnapshot {
        try await saveSnapshot(
            snapshot,
            using: descriptor,
            expectedRecordChangeTag: expectedRecordChangeTag,
            acceptedPredecessorOperationIDs: acceptedPredecessorOperationIDs,
            requiresKnownBaseline: descriptor.role != .local
        )
    }

    func recreateSnapshotAfterEncryptedDataReset(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        acceptedPredecessorOperationIDs: Set<UUID> = []
    ) async throws -> SavedRepositorySnapshot {
        guard descriptor.role == .owner else {
            throw CloudRepositoryError.repositoryLocked
        }

        var resetDescriptor = descriptor
        resetDescriptor.shareRecordName = nil
        return try await saveSnapshot(
            snapshot,
            using: resetDescriptor,
            expectedRecordChangeTag: nil,
            acceptedPredecessorOperationIDs: acceptedPredecessorOperationIDs,
            requiresKnownBaseline: false
        )
    }

    private func saveSnapshot(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        expectedRecordChangeTag: String?,
        acceptedPredecessorOperationIDs: Set<UUID>,
        requiresKnownBaseline: Bool
    ) async throws -> SavedRepositorySnapshot {
        guard descriptor.role.canEdit else {
            throw CloudRepositoryError.repositoryLocked
        }
        var uploadSnapshot = snapshot
        uploadSnapshot.imageContentHashes = try Self.imageContentHashes(
            in: snapshot
        )

        var normalizedDescriptor = descriptor
        if normalizedDescriptor.role == .local {
            normalizedDescriptor = RepositoryDescriptor(
                zoneName: Constant.zoneName,
                zoneOwnerName: CKCurrentUserDefaultName,
                shareRecordName: nil,
                role: .owner
            )
        }

        guard let zoneID = normalizedDescriptor.zoneID else {
            throw CloudRepositoryError.repositoryDescriptorMissing
        }

        let database = database(for: normalizedDescriptor.role)
        try await saveZoneIfNeeded(zoneID: zoneID, in: database)
        let recordID = CKRecord.ID(recordName: Constant.rootRecordName, zoneID: zoneID)
        let existingRecord = try await fetchRecordIfPresent(
            recordID: recordID,
            in: database
        )
        if !requiresKnownBaseline,
           existingRecord != nil {
            let remoteOperationID = try existingRecord.flatMap {
                try Self.cloudUploadOperationID(from: $0)
            }
            if remoteOperationID == snapshot.cloudUploadOperationID,
               let existingRecord {
                return SavedRepositorySnapshot(
                    descriptor: normalizedDescriptor,
                    serverModifiedAt: existingRecord.modificationDate,
                    recordChangeTag: existingRecord.recordChangeTag
                )
            }
            guard let remoteOperationID,
                  acceptedPredecessorOperationIDs.contains(remoteOperationID),
                  existingRecord != nil else {
                throw CloudRepositoryError.repositoryConflict(
                    serverRecordChangeTag: existingRecord?.recordChangeTag
                )
            }
        }
        if requiresKnownBaseline {
            let baselineMatches =
                expectedRecordChangeTag != nil &&
                existingRecord?.recordChangeTag == expectedRecordChangeTag
            if !baselineMatches {
                let remoteOperationID = try existingRecord.flatMap {
                    try Self.cloudUploadOperationID(from: $0)
                }
                if remoteOperationID == snapshot.cloudUploadOperationID,
                   let existingRecord {
                    return SavedRepositorySnapshot(
                        descriptor: normalizedDescriptor,
                        serverModifiedAt: existingRecord.modificationDate,
                        recordChangeTag: existingRecord.recordChangeTag
                    )
                }
                guard let remoteOperationID,
                      acceptedPredecessorOperationIDs.contains(remoteOperationID),
                      existingRecord != nil else {
                    throw CloudRepositoryError.repositoryConflict(
                        serverRecordChangeTag: existingRecord?.recordChangeTag
                    )
                }
            }
            guard existingRecord != nil else {
                throw CloudRepositoryError.repositoryConflict(
                    serverRecordChangeTag: existingRecord?.recordChangeTag
                )
            }
        }
        let previousSnapshot = try existingRecord.map {
            try Self.repositorySnapshot(from: $0)
        }
        let imageMutationPlan = try Self.imageMutationPlan(
            for: uploadSnapshot,
            replacing: previousSnapshot
        )
        let record = existingRecord ??
            CKRecord(recordType: Constant.recordType, recordID: recordID)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let archiveData = try encoder.encode(
            uploadSnapshot.removingEmbeddedImages()
        )
        let temporaryFile = try TemporaryAssetFile(data: archiveData, fileExtension: "json")

        let preparedImageAssets = try await prepareImageAssetsForSave(
            imageMutationPlan.assetsToSave,
            referencesToInspect:
                Set(imageMutationPlan.referencesToInspectBeforeSave),
            zoneID: zoneID,
            in: database
        )
        let imageRecordIDsToDelete =
            try await existingImageRecordIDs(
                references: imageMutationPlan.referencesToDelete,
                zoneID: zoneID,
                in: database
            )

        record[Constant.updatedAtKey] =
            uploadSnapshot.updatedAt as CKRecordValue
        record[Constant.entryCountKey] =
            uploadSnapshot.entries.count as CKRecordValue
        record[Constant.payloadKey] = CKAsset(fileURL: temporaryFile.url)

        let savedRecord: CKRecord
        do {
            savedRecord = try await saveRepositoryRecordsAtomically(
                rootRecord: record,
                imageRecords: preparedImageAssets.records,
                imageRecordIDsToDelete: imageRecordIDsToDelete,
                in: database
            )
        } catch let cloudError as CKError where cloudError.code == .serverRecordChanged {
            let serverRecord = (cloudError as NSError)
                .userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
            throw CloudRepositoryError.repositoryConflict(
                serverRecordChangeTag: serverRecord?.recordChangeTag
            )
        }
        _ = temporaryFile
        _ = preparedImageAssets.temporaryFiles

        if normalizedDescriptor.role == .owner,
           let share = try await fetchShareIfPresent(zoneID: zoneID, in: privateDatabase) {
            normalizedDescriptor.shareRecordName = share.recordID.recordName
        }

        return SavedRepositorySnapshot(
            descriptor: normalizedDescriptor,
            serverModifiedAt: savedRecord.modificationDate,
            recordChangeTag: savedRecord.recordChangeTag
        )
    }

    func ensureRepositorySubscription(using descriptor: RepositoryDescriptor) async throws {
        let subscription: CKDatabaseSubscription
        let database: CKDatabase
        let obsoleteSubscriptionIDs: [CKSubscription.ID]

        switch descriptor.role {
        case .local:
            return
        case .owner:
            database = privateDatabase
            subscription = CKDatabaseSubscription(
                subscriptionID: Constant.privateDatabaseSubscriptionID
            )
            obsoleteSubscriptionIDs = legacySubscriptionIDs(for: descriptor)
        case .editor, .viewer:
            database = sharedDatabase
            subscription = CKDatabaseSubscription(subscriptionID: Constant.sharedDatabaseSubscriptionID)
            obsoleteSubscriptionIDs = [Constant.legacySharedDatabaseSubscriptionID]
        }

        subscription.recordType = Constant.recordType
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let candidateIDs = Array(
            Set([subscription.subscriptionID] + obsoleteSubscriptionIDs)
        )
        let existingSubscriptions = try await database.subscriptions(for: candidateIDs)
        for result in existingSubscriptions.values {
            if case let .failure(error) = result,
               !Self.isUnknownItemError(error) {
                throw error
            }
        }

        let currentSubscription: CKDatabaseSubscription?
        if case let .success(existing)? = existingSubscriptions[subscription.subscriptionID] {
            currentSubscription = existing as? CKDatabaseSubscription
        } else {
            currentSubscription = nil
        }
        let isCurrentConfiguration =
            currentSubscription?.recordType == Constant.recordType &&
            currentSubscription?.notificationInfo?.shouldSendContentAvailable == true
        let obsoleteExistingIDs = obsoleteSubscriptionIDs.filter {
            if case .success? = existingSubscriptions[$0] {
                return $0 != subscription.subscriptionID
            }
            return false
        }
        guard !isCurrentConfiguration || !obsoleteExistingIDs.isEmpty else {
            return
        }

        let subscriptionsToSave = isCurrentConfiguration ? [] : [subscription]
        let result = try await database.modifySubscriptions(
            saving: subscriptionsToSave,
            deleting: obsoleteExistingIDs
        )
        if !isCurrentConfiguration {
            switch result.saveResults[subscription.subscriptionID] {
            case .success:
                break
            case .failure(let error):
                throw error
            case nil:
                throw CloudRepositoryError.shareUnavailable
            }
        }
        for subscriptionID in obsoleteExistingIDs {
            if case let .failure(error)? = result.deleteResults[subscriptionID],
               !Self.isUnknownItemError(error) {
                throw error
            }
        }
    }

    func pendingRepositoryZoneChanges(
        in scope: CloudDatabaseScope
    ) async throws -> CloudRepositoryDatabaseChanges {
        let database: CKDatabase
        switch scope {
        case .privateDatabase:
            database = privateDatabase
        case .sharedDatabase:
            database = sharedDatabase
        }

        let storedChangeToken: CKServerChangeToken?
        do {
            storedChangeToken = try changeTokenStore?.loadToken(for: scope)
        } catch {
            try? changeTokenStore?.removeToken(for: scope)
            storedChangeToken = nil
        }

        var changeToken = storedChangeToken
        var changes = CloudRepositoryDatabaseChanges(
            modifiedZoneIDs: try changeTokenStore?.loadPendingZoneIDs(for: scope) ?? [],
            deletedZones: try changeTokenStore?.loadPendingDeletedZones(for: scope) ?? []
        )
        var didRecoverExpiredToken = false

        while true {
            do {
                let databaseChanges = try await database.databaseChanges(since: changeToken)
                for modification in databaseChanges.modifications {
                    let zoneID = CloudRepositoryZoneIdentity(
                        zoneID: modification.zoneID
                    )
                    changes.modifiedZoneIDs.insert(zoneID)
                    changes.deletedZones = Set(
                        changes.deletedZones.filter { $0.zoneID != zoneID }
                    )
                }
                for deletion in databaseChanges.deletions {
                    let zoneID = CloudRepositoryZoneIdentity(
                        zoneID: deletion.zoneID
                    )
                    let reason: CloudRepositoryZoneDeletionReason
                    switch deletion.reason {
                    case .deleted:
                        reason = .deleted
                    case .purged:
                        reason = .purged
                    case .encryptedDataReset:
                        reason = .encryptedDataReset
                    @unknown default:
                        reason = .deleted
                    }
                    changes.modifiedZoneIDs.remove(zoneID)
                    changes.deletedZones = Set(
                        changes.deletedZones.filter { $0.zoneID != zoneID }
                    )
                    changes.deletedZones.insert(
                        CloudRepositoryZoneDeletion(
                            zoneID: zoneID,
                            reason: reason
                        )
                    )
                }
                try changeTokenStore?.savePendingZoneIDs(
                    changes.modifiedZoneIDs,
                    for: scope
                )
                try changeTokenStore?.savePendingDeletedZones(
                    changes.deletedZones,
                    for: scope
                )
                try changeTokenStore?.saveToken(databaseChanges.changeToken, for: scope)
                changeToken = databaseChanges.changeToken

                if !databaseChanges.moreComing {
                    return changes
                }
            } catch {
                guard !didRecoverExpiredToken,
                      let cloudError = error as? CKError,
                      cloudError.code == .changeTokenExpired else {
                    throw error
                }

                didRecoverExpiredToken = true
                changeToken = nil
                try changeTokenStore?.removeToken(for: scope)
            }
        }
    }

    func acknowledgeRepositoryZoneChanges(
        _ changes: CloudRepositoryDatabaseChanges,
        in scope: CloudDatabaseScope
    ) async throws {
        try changeTokenStore?.acknowledgePendingZoneIDs(
            changes.modifiedZoneIDs,
            for: scope
        )
        try changeTokenStore?.acknowledgePendingDeletedZones(
            changes.deletedZones,
            for: scope
        )
    }

    func resetRemoteChangeTracking() async throws {
        try changeTokenStore?.removeAllTrackingState()
    }

    @MainActor
    func makeSharingController(
        using descriptor: RepositoryDescriptor,
        snapshot: RepositorySnapshot,
        access: ShareAccessOption
    ) async throws -> UICloudSharingController {
        guard descriptor.role == .owner,
              let zoneID = descriptor.zoneID else {
            throw CloudRepositoryError.shareUnavailable
        }

        let share = try await fetchOrCreateShare(zoneID: zoneID)
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = access.permissionOptions
        return controller
    }

    func acceptShare(from url: URL) async throws -> AcceptedSharedRepository {
        let metadata = try await shareMetadata(for: url)
        return try await acceptShare(metadata: metadata)
    }

    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository {
        _ = try await container.accept([metadata])

        let shareRecord = metadata.share
        let permission = shareRecord.currentUserParticipant?.permission ?? .readOnly
        let role: RepositoryRole = permission == .readWrite ? .editor : .viewer
        let ownerDisplayName = metadata.ownerIdentity.nameComponents.flatMap { components in
            PersonNameComponentsFormatter.localizedString(from: components, style: .default, options: [])
                .trimmed
                .nilIfEmpty
        }
        let descriptor = RepositoryDescriptor(
            zoneName: shareRecord.recordID.zoneID.zoneName,
            zoneOwnerName: shareRecord.recordID.zoneID.ownerName,
            shareRecordName: shareRecord.recordID.recordName,
            role: role
        )
        let loadedRepository = try await loadSnapshotWithMetadata(using: descriptor)
        return AcceptedSharedRepository(
            descriptor: descriptor,
            snapshot: loadedRepository.snapshot,
            displayName: L10n.sharedRepositoryDisplayName(ownerName: ownerDisplayName),
            serverModifiedAt: loadedRepository.metadata.serverModifiedAt,
            recordChangeTag: loadedRepository.metadata.recordChangeTag
        )
    }

    private func database(for role: RepositoryRole) -> CKDatabase {
        switch role {
        case .local, .owner:
            privateDatabase
        case .editor, .viewer:
            sharedDatabase
        }
    }

    private func saveZoneIfNeeded(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        if try await fetchZoneIfPresent(zoneID: zoneID, in: database) != nil {
            return
        }

        let result = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        guard case .success = result.saveResults[zoneID] else {
            if case let .failure(error)? = result.saveResults[zoneID] {
                throw error
            }

            throw CloudRepositoryError.repositoryNotFound
        }
    }

    private func fetchOrCreateShare(zoneID: CKRecordZone.ID) async throws -> CKShare {
        if let share = try await fetchShareIfPresent(zoneID: zoneID, in: privateDatabase) {
            return share
        }

        let share = CKShare(recordZoneID: zoneID)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = L10n.string("thatDay Repository") as CKRecordValue
        guard let savedShare = try await saveRecord(share, in: privateDatabase) as? CKShare else {
            throw CloudRepositoryError.shareUnavailable
        }

        return savedShare
    }

    private func fetchShareIfPresent(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> CKShare? {
        guard let zone = try await fetchZoneIfPresent(zoneID: zoneID, in: database),
              let shareReference = zone.share else {
            return nil
        }

        return try await fetchRecordIfPresent(recordID: shareReference.recordID, in: database) as? CKShare
    }

    private func fetchZoneIfPresent(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> CKRecordZone? {
        let results = try await database.recordZones(for: [zoneID])
        switch results[zoneID] {
        case .success(let zone):
            return zone
        case .failure(let error):
            if let ckError = error as? CKError, ckError.code == .zoneNotFound {
                return nil
            }
            throw error
        case nil:
            return nil
        }
    }

    private func fetchRecordIfPresent(
        recordID: CKRecord.ID,
        in database: CKDatabase,
        desiredKeys: [CKRecord.FieldKey]? = nil
    ) async throws -> CKRecord? {
        let results = try await database.records(for: [recordID], desiredKeys: desiredKeys)
        switch results[recordID] {
        case .success(let record):
            return record
        case .failure(let error):
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                return nil
            }
            throw error
        case nil:
            return nil
        }
    }

    private func fetchImageAssets(
        references: [String],
        expectedContentHashes: [String: String],
        zoneID: CKRecordZone.ID,
        in database: CKDatabase
    ) async throws -> [RepositoryImageAsset] {
        guard !references.isEmpty else {
            return []
        }

        var assetsByReference: [String: RepositoryImageAsset] = [:]

        for batch in Self.chunks(references, size: Constant.recordBatchSize) {
            let idsByReference = Dictionary(
                uniqueKeysWithValues: batch.map { reference in
                    (
                        reference,
                        CKRecord.ID(recordName: Self.imageRecordName(for: reference), zoneID: zoneID)
                    )
                }
            )
            let results = try await database.records(
                for: Array(idsByReference.values),
                desiredKeys: [
                    Constant.referenceKey,
                    Constant.contentHashKey,
                    Constant.payloadKey
                ]
            )

            for reference in batch {
                guard let recordID = idsByReference[reference],
                      let result = results[recordID] else {
                    continue
                }

                switch result {
                case .success(let record):
                    guard let asset = record[Constant.payloadKey] as? CKAsset,
                          let data = try Self.assetData(from: asset) else {
                        continue
                    }

                    assetsByReference[reference] =
                        try Self.validatedImageAsset(
                            requestedReference: reference,
                            storedReference:
                                record[Constant.referenceKey] as? String,
                            recordedContentHash:
                                record[Constant.contentHashKey] as? String,
                            expectedContentHash:
                                expectedContentHashes[reference],
                            data: data
                    )
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        continue
                    }

                    throw error
                }
            }
        }

        guard Set(assetsByReference.keys) == Set(references) else {
            throw CloudRepositoryError.invalidRepositoryData
        }
        return references.compactMap { assetsByReference[$0] }
    }

    private func prepareImageAssetsForSave(
        _ assets: [RepositoryImageAsset],
        referencesToInspect: Set<String>,
        zoneID: CKRecordZone.ID,
        in database: CKDatabase
    ) async throws -> (
        records: [CKRecord],
        temporaryFiles: [TemporaryAssetFile]
    ) {
        guard !assets.isEmpty else {
            return ([], [])
        }

        let uniqueAssets = Dictionary(assets.map { ($0.reference, $0) }) { _, latest in latest }
        var existingRecordsByReference: [String: CKRecord] = [:]
        for batch in Self.chunks(
            Array(referencesToInspect).sorted(),
            size: Constant.recordBatchSize
        ) {
            let idsByReference = Dictionary(
                uniqueKeysWithValues: batch.map { reference in
                    (
                        reference,
                        CKRecord.ID(
                            recordName: Self.imageRecordName(for: reference),
                            zoneID: zoneID
                        )
                    )
                }
            )
            let results = try await database.records(
                for: Array(idsByReference.values),
                desiredKeys: [
                    Constant.referenceKey,
                    Constant.contentHashKey
                ]
            )
            for reference in batch {
                guard let recordID = idsByReference[reference],
                      let result = results[recordID] else {
                    continue
                }
                switch result {
                case .success(let record):
                    existingRecordsByReference[reference] = record
                case .failure(let error):
                    if let cloudError = error as? CKError,
                       cloudError.code == .unknownItem {
                        continue
                    }
                    throw error
                }
            }
        }

        var allRecordsToSave: [CKRecord] = []
        var allTemporaryFiles: [TemporaryAssetFile] = []

        for batch in Self.chunks(
            Array(uniqueAssets.keys).sorted(),
            size: Constant.recordBatchSize
        ) {
            let recordsToSave: [CKRecord] = try batch.compactMap { reference in
                guard let asset = uniqueAssets[reference] else {
                    return nil
                }

                let contentHash = Self.contentHash(for: asset.data)
                let recordID = CKRecord.ID(
                    recordName: Self.imageRecordName(for: reference),
                    zoneID: zoneID
                )
                let record: CKRecord
                if let existingRecord =
                    existingRecordsByReference[reference] {
                    if existingRecord[Constant.contentHashKey] as? String ==
                        contentHash {
                        return nil
                    }
                    record = existingRecord
                } else {
                    record = CKRecord(
                        recordType: Constant.imageRecordType,
                        recordID: recordID
                    )
                }
                let temporaryFile = try TemporaryAssetFile(data: asset.data, fileExtension: "jpg")
                allTemporaryFiles.append(temporaryFile)
                record[Constant.referenceKey] = reference as CKRecordValue
                record[Constant.contentHashKey] = contentHash as CKRecordValue
                record[Constant.payloadKey] = CKAsset(fileURL: temporaryFile.url)
                return record
            }

            allRecordsToSave.append(contentsOf: recordsToSave)
            guard allRecordsToSave.count + 1 <= Constant.maximumAtomicRecordsPerSave else {
                throw CloudRepositoryError.atomicSaveLimitExceeded
            }
        }

        return (allRecordsToSave, allTemporaryFiles)
    }

    private func existingImageRecordIDs(
        references: [String],
        zoneID: CKRecordZone.ID,
        in database: CKDatabase
    ) async throws -> [CKRecord.ID] {
        var existingRecordIDs: [CKRecord.ID] = []
        for batch in Self.chunks(
            references,
            size: Constant.recordBatchSize
        ) {
            let recordIDs = batch.map {
                CKRecord.ID(
                    recordName: Self.imageRecordName(for: $0),
                    zoneID: zoneID
                )
            }
            let results = try await database.records(
                for: recordIDs,
                desiredKeys: []
            )
            for recordID in recordIDs {
                switch results[recordID] {
                case .success:
                    existingRecordIDs.append(recordID)
                case .failure(let error):
                    if let cloudError = error as? CKError,
                       cloudError.code == .unknownItem {
                        continue
                    }
                    throw error
                case nil:
                    continue
                }
            }
        }
        return existingRecordIDs
    }

    private func saveRepositoryRecordsAtomically(
        rootRecord: CKRecord,
        imageRecords: [CKRecord],
        imageRecordIDsToDelete: [CKRecord.ID],
        in database: CKDatabase
    ) async throws -> CKRecord {
        let recordsToSave = [rootRecord] + imageRecords
        guard recordsToSave.count + imageRecordIDsToDelete.count <=
                Constant.maximumAtomicRecordsPerSave else {
            throw CloudRepositoryError.atomicSaveLimitExceeded
        }

        let result: (
            saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
            deleteResults: [CKRecord.ID: Result<Void, any Error>]
        )
        do {
            result = try await database.modifyRecords(
                saving: recordsToSave,
                deleting: imageRecordIDsToDelete,
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
        } catch {
            if Self.containsServerRecordChangedError(error) {
                throw CloudRepositoryError.repositoryConflict(
                    serverRecordChangeTag: rootRecord.recordChangeTag
                )
            }
            throw error
        }

        for record in recordsToSave {
            if case let .failure(error)? = result.saveResults[record.recordID],
               Self.containsServerRecordChangedError(error) {
                throw CloudRepositoryError.repositoryConflict(
                    serverRecordChangeTag: rootRecord.recordChangeTag
                )
            }
        }

        let savedRootRecord: CKRecord
        switch result.saveResults[rootRecord.recordID] {
        case .success(let record):
            savedRootRecord = record
        case .failure(let error):
            throw error
        case nil:
            throw CloudRepositoryError.repositoryNotFound
        }

        for imageRecord in imageRecords {
            switch result.saveResults[imageRecord.recordID] {
            case .success:
                continue
            case .failure(let error):
                throw error
            case nil:
                throw CloudRepositoryError.repositoryNotFound
            }
        }
        for recordID in imageRecordIDsToDelete {
            switch result.deleteResults[recordID] {
            case .success:
                continue
            case .failure(let error):
                throw error
            case nil:
                throw CloudRepositoryError.repositoryNotFound
            }
        }
        return savedRootRecord
    }

    nonisolated private static func containsServerRecordChangedError(_ error: Error) -> Bool {
        if let cloudError = error as? CKError,
           cloudError.code == .serverRecordChanged {
            return true
        }

        let nsError = error as NSError
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           containsServerRecordChangedError(underlyingError) {
            return true
        }
        if nsError.domain == CKErrorDomain,
           let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            return partialErrors.values.contains(where: containsServerRecordChangedError)
        }
        return false
    }

    private func saveRecord(_ record: CKRecord, in database: CKDatabase) async throws -> CKRecord {
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        switch result.saveResults[record.recordID] {
        case .success(let savedRecord):
            return savedRecord
        case .failure(let error):
            throw error
        case nil:
            throw CloudRepositoryError.repositoryNotFound
        }
    }

    private func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        let results = try await container.shareMetadatas(for: [url])
        switch results[url] {
        case .success(let metadata):
            return metadata
        case .failure(let error):
            throw error
        case nil:
            throw CloudRepositoryError.shareLinkInvalid
        }
    }

    private static func assetData(from asset: CKAsset) throws -> Data? {
        guard let url = asset.fileURL else {
            return nil
        }

        return try Data(contentsOf: url)
    }

    private static func cloudUploadOperationID(from record: CKRecord) throws -> UUID? {
        try repositorySnapshot(from: record).cloudUploadOperationID
    }

    private static func repositorySnapshot(
        from record: CKRecord
    ) throws -> RepositorySnapshot {
        guard let asset = record[Constant.payloadKey] as? CKAsset,
              let data = try assetData(from: asset) else {
            throw CloudRepositoryError.invalidRepositoryData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RepositorySnapshot.self, from: data)
    }

    nonisolated private static func imageRecordName(
        for reference: String
    ) -> String {
        "RepositoryImageAsset-\(reference)"
    }

    nonisolated private static func contentHash(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    nonisolated private static func chunks<T>(
        _ values: [T],
        size: Int
    ) -> [[T]] {
        guard size > 0 else {
            return [values]
        }

        return stride(from: 0, to: values.count, by: size).map { startIndex in
            Array(values[startIndex..<min(startIndex + size, values.count)])
        }
    }

    nonisolated private static func localImageReferences(
        in snapshot: RepositorySnapshot
    ) -> Set<String> {
        Set(snapshot.entries.compactMap { localImageReference($0.imageReference) })
    }

    nonisolated private static func localImageReference(
        _ reference: String?
    ) -> String? {
        guard let value = reference?.trimmed.nilIfEmpty else {
            return nil
        }

        if let parsedURL = URL(string: value),
           let scheme = parsedURL.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return nil
            case "file":
                return parsedURL.lastPathComponent.trimmed.nilIfEmpty
            default:
                break
            }
        }

        let lastPathComponent = URL(fileURLWithPath: value).lastPathComponent.trimmed
        return lastPathComponent.nilIfEmpty
    }

    private func legacySubscriptionIDs(for descriptor: RepositoryDescriptor) -> [CKSubscription.ID] {
        var descriptors = [descriptor]
        var descriptorWithoutShare = descriptor
        descriptorWithoutShare.shareRecordName = nil
        descriptors.append(descriptorWithoutShare)

        return Array(
            Set(descriptors.map { "repository-updates-\($0.storageIdentifier)" })
        )
    }

    private static func isUnknownItemError(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else {
            return false
        }

        return cloudError.code == .unknownItem
    }
}

private extension ShareAccessOption {
    var permissionOptions: UICloudSharingController.PermissionOptions {
        switch self {
        case .viewOnly:
            [.allowPrivate, .allowReadOnly]
        case .editable:
            [.allowPrivate, .allowReadWrite]
        }
    }
}

private final class TemporaryAssetFile {
    let url: URL

    init(data: Data, fileExtension: String) throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thatDay-cloudkit", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        url = directoryURL.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
