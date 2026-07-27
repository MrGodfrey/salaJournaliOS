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

nonisolated struct LoadedRepositorySnapshot: Equatable, Sendable {
    var snapshot: RepositorySnapshot
    var metadata: RepositorySnapshotMetadata
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

nonisolated enum CloudAccountAvailability: Equatable, Sendable {
    case available(userRecordName: String)
    case temporarilyUnavailable
    case unavailable
}

nonisolated struct CloudSubscriptionRepairPlan: Sendable {
    var subscriptionToSave: CKSubscription?
    var subscriptionIDsToDelete: [CKSubscription.ID]
}

protocol CloudRepositoryServicing {
    var requiresExplicitAccountIdentityMigrationConfirmation:
        Bool { get }

    func loadSnapshotMetadata(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshotMetadata
    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot
    func loadSnapshot(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String]
    ) async throws -> RepositorySnapshot
    func loadSnapshotWithMetadata(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String]
    ) async throws -> LoadedRepositorySnapshot
    func saveSnapshot(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        expectedRecordChangeTag: String?,
        acceptedPredecessorOperationIDs: Set<UUID>
    ) async throws -> SavedRepositorySnapshot
    func validatedDescriptorForUpload(
        using descriptor: RepositoryDescriptor
    ) async throws -> RepositoryDescriptor
    func recreateSnapshotAfterEncryptedDataReset(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        acceptedPredecessorOperationIDs: Set<UUID>
    ) async throws -> SavedRepositorySnapshot
    func ensureRepositorySubscription(using descriptor: RepositoryDescriptor) async throws
    func ensureRepositorySubscriptions(
        using descriptors: [RepositoryDescriptor]
    ) async throws
    func cloudAccountAvailability() async throws
        -> CloudAccountAvailability
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
    var requiresExplicitAccountIdentityMigrationConfirmation:
        Bool {
        true
    }

    func loadSnapshot(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String]
    ) async throws -> RepositorySnapshot {
        try await loadSnapshot(using: descriptor)
    }

    func loadSnapshotWithMetadata(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String]
    ) async throws -> LoadedRepositorySnapshot {
        let snapshot = try await loadSnapshot(
            using: descriptor,
            availableImageContentHashes:
                availableImageContentHashes
        )
        let metadata = try await loadSnapshotMetadata(using: descriptor)
        return LoadedRepositorySnapshot(
            snapshot: snapshot,
            metadata: metadata
        )
    }

    func ensureRepositorySubscriptions(
        using descriptors: [RepositoryDescriptor]
    ) async throws {
        for descriptor in descriptors {
            try await ensureRepositorySubscription(using: descriptor)
        }
    }

    func cloudAccountAvailability() async throws
        -> CloudAccountAvailability {
        .available(userRecordName: "default-cloud-account")
    }

    func validatedDescriptorForUpload(
        using descriptor: RepositoryDescriptor
    ) async throws -> RepositoryDescriptor {
        descriptor
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
    nonisolated private enum Constant {
        static let zoneName = "thatday-repository"
        static let rootRecordName = "RepositoryRoot"
        static let recordType = "RepositoryRoot"
        static let imageRecordType = "RepositoryImageAsset"
        // These are the stable subscription configurations shipped before
        // 1.2.9 and already exercised in CloudKit's production environment.
        static let stableSharedDatabaseSubscriptionID =
            "repository-updates-shared-database"
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

    func cloudAccountAvailability() async throws
        -> CloudAccountAvailability {
        switch try await container.accountStatus() {
        case .available:
            let userRecordID = try await container.userRecordID()
            return .available(
                userRecordName: userRecordID.recordName
            )
        case .temporarilyUnavailable, .couldNotDetermine:
            return .temporarilyUnavailable
        case .noAccount, .restricted:
            return .unavailable
        @unknown default:
            return .temporarilyUnavailable
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

    func loadSnapshotWithMetadata(
        using descriptor: RepositoryDescriptor,
        availableImageContentHashes: [String: String] = [:]
    ) async throws -> LoadedRepositorySnapshot {
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
        return LoadedRepositorySnapshot(
            snapshot: hydratedSnapshot,
            metadata: metadata
        )
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

    func validatedDescriptorForUpload(
        using descriptor: RepositoryDescriptor
    ) async throws -> RepositoryDescriptor {
        guard descriptor.role.canEdit else {
            return descriptor
        }
        guard descriptor.role == .editor else {
            return descriptor
        }
        guard let zoneID = descriptor.zoneID,
              let shareRecordName =
                descriptor.shareRecordName else {
            throw CloudRepositoryError.repositoryDescriptorMissing
        }

        let shareRecordID = CKRecord.ID(
            recordName: shareRecordName,
            zoneID: zoneID
        )
        guard let share = try await fetchRecordIfPresent(
            recordID: shareRecordID,
            in: sharedDatabase
        ) as? CKShare else {
            throw CloudRepositoryError.repositoryNotFound
        }
        var validatedDescriptor = descriptor
        validatedDescriptor.role =
            share.currentUserParticipant?.permission == .readWrite
                ? .editor
                : .viewer
        return validatedDescriptor
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
        try await ensureRepositorySubscriptions(using: [descriptor])
    }

    func ensureRepositorySubscriptions(
        using descriptors: [RepositoryDescriptor]
    ) async throws {
        let cloudDescriptors = descriptors.filter(\.isCloudBacked)
        let ownerDescriptors = cloudDescriptors.filter {
            $0.role == .owner
        }
        let sharedDescriptors = cloudDescriptors.filter {
            $0.role == .editor || $0.role == .viewer
        }

        if !ownerDescriptors.isEmpty {
            try await ensureRepositorySubscriptions(
                using: ownerDescriptors,
                in: privateDatabase
            )
        }
        if !sharedDescriptors.isEmpty {
            try await ensureRepositorySubscriptions(
                using: sharedDescriptors,
                in: sharedDatabase
            )
        }
    }

    private func ensureRepositorySubscriptions(
        using descriptors: [RepositoryDescriptor],
        in database: CKDatabase
    ) async throws {
        let existingSubscriptions = try await database.allSubscriptions()
        let repairPlans = descriptors.map {
            Self.subscriptionRepairPlan(
                using: $0,
                existingSubscriptions: existingSubscriptions
            )
        }
        let subscriptionsToSave = Dictionary(
            repairPlans.compactMap(\.subscriptionToSave).map {
                ($0.subscriptionID, $0)
            },
            uniquingKeysWith: { existing, _ in existing }
        )
        guard !subscriptionsToSave.isEmpty else {
            return
        }

        // Intentionally never combine a repair save with a deletion. CloudKit
        // reports subscription modifications per item, so a replacement save
        // can fail while an old working subscription is still deleted.
        let result = try await database.modifySubscriptions(
            saving: Array(subscriptionsToSave.values),
            deleting: []
        )
        for (subscriptionID, subscription) in subscriptionsToSave {
            let matchingDescriptors = descriptors.filter {
                Self.isStableRepositorySubscription(subscription, for: $0)
            }
            guard !matchingDescriptors.isEmpty else {
                throw CloudRepositoryError.shareUnavailable
            }
            switch result.saveResults[subscriptionID] {
            case .success(let savedSubscription):
                guard matchingDescriptors.contains(where: {
                    Self.isStableRepositorySubscription(
                        savedSubscription,
                        for: $0
                    )
                }) else {
                    throw CloudRepositoryError.shareUnavailable
                }
            case .failure(let error):
                throw error
            case nil:
                throw CloudRepositoryError.shareUnavailable
            }
        }

        // Do not mark the repair successful from the modify response alone.
        // Read it back so a partial or server-side configuration failure cannot
        // leave the catalog claiming that push delivery is configured.
        let verificationResults = try await database.subscriptions(
            for: Array(subscriptionsToSave.keys)
        )
        for (subscriptionID, subscription) in subscriptionsToSave {
            let matchingDescriptors = descriptors.filter {
                Self.isStableRepositorySubscription(subscription, for: $0)
            }
            switch verificationResults[subscriptionID] {
            case .success(let verifiedSubscription):
                guard matchingDescriptors.contains(where: {
                    Self.isStableRepositorySubscription(
                        verifiedSubscription,
                        for: $0
                    )
                }) else {
                    throw CloudRepositoryError.shareUnavailable
                }
            case .failure(let error):
                throw error
            case nil:
                throw CloudRepositoryError.shareUnavailable
            }
        }
    }

    nonisolated static func subscriptionRepairPlan(
        using descriptor: RepositoryDescriptor,
        existingSubscriptions: [CKSubscription]
    ) -> CloudSubscriptionRepairPlan {
        if existingSubscriptions.contains(where: {
            isStableRepositorySubscription($0, for: descriptor)
        }) {
            return CloudSubscriptionRepairPlan(
                subscriptionToSave: nil,
                subscriptionIDsToDelete: []
            )
        }

        return CloudSubscriptionRepairPlan(
            subscriptionToSave: stableSubscription(for: descriptor),
            // A repair must never delete a working fallback. CloudKit
            // subscription modifications can partially succeed, so cleanup
            // belongs in a later release after field verification.
            subscriptionIDsToDelete: []
        )
    }

    nonisolated static func isStableRepositorySubscription(
        _ subscription: CKSubscription,
        for descriptor: RepositoryDescriptor
    ) -> Bool {
        guard isSilentOnlyNotificationInfo(subscription.notificationInfo)
        else {
            return false
        }

        switch descriptor.role {
        case .local:
            return false
        case .owner:
            guard let expectedZoneID = descriptor.zoneID,
                  let zoneSubscription =
                    subscription as? CKRecordZoneSubscription else {
                return false
            }
            return zoneSubscription.zoneID == expectedZoneID &&
                zoneSubscription.recordType == nil
        case .editor, .viewer:
            guard subscription.subscriptionID ==
                    Constant.stableSharedDatabaseSubscriptionID,
                  let databaseSubscription =
                    subscription as? CKDatabaseSubscription else {
                return false
            }
            return databaseSubscription.recordType == nil
        }
    }

    nonisolated static func isSilentOnlyNotificationInfo(
        _ notificationInfo: CKSubscription.NotificationInfo?
    ) -> Bool {
        guard let notificationInfo,
              notificationInfo.shouldSendContentAvailable,
              notificationInfo.alertBody == nil,
              notificationInfo.alertLocalizationKey == nil,
              notificationInfo.alertLocalizationArgs?.isEmpty != false,
              notificationInfo.title == nil,
              notificationInfo.titleLocalizationKey == nil,
              notificationInfo.titleLocalizationArgs?.isEmpty != false,
              notificationInfo.subtitle == nil,
              notificationInfo.subtitleLocalizationKey == nil,
              notificationInfo.subtitleLocalizationArgs?.isEmpty != false,
              notificationInfo.alertActionLocalizationKey == nil,
              notificationInfo.alertLaunchImage == nil,
              notificationInfo.soundName == nil,
              notificationInfo.desiredKeys?.isEmpty != false,
              !notificationInfo.shouldBadge,
              !notificationInfo.shouldSendMutableContent,
              notificationInfo.category == nil,
              notificationInfo.collapseIDKey == nil else {
            return false
        }
        return true
    }

    nonisolated private static func stableSubscription(
        for descriptor: RepositoryDescriptor
    ) -> CKSubscription? {
        let subscription: CKSubscription
        switch descriptor.role {
        case .local:
            return nil
        case .owner:
            guard let zoneID = descriptor.zoneID else {
                return nil
            }
            var stableDescriptor = descriptor
            stableDescriptor.shareRecordName = nil
            subscription = CKRecordZoneSubscription(
                zoneID: zoneID,
                subscriptionID: legacySubscriptionID(
                    for: stableDescriptor
                )
            )
        case .editor, .viewer:
            subscription = CKDatabaseSubscription(
                subscriptionID: Constant.stableSharedDatabaseSubscriptionID
            )
        }

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        return subscription
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

    nonisolated private static func legacySubscriptionID(
        for descriptor: RepositoryDescriptor
    ) -> CKSubscription.ID {
        "repository-updates-\(descriptor.storageIdentifier)"
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
