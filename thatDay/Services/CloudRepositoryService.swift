import CloudKit
import CryptoKit
import Foundation
import UIKit

struct RepositorySnapshotMetadata: Equatable, Sendable {
    var updatedAt: Date
    var entryCount: Int
}

protocol CloudRepositoryServicing {
    func loadSnapshotMetadata(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshotMetadata
    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot
    func saveSnapshot(_ snapshot: RepositorySnapshot, using descriptor: RepositoryDescriptor) async throws -> RepositoryDescriptor
    func shareURL(using descriptor: RepositoryDescriptor, snapshot: RepositorySnapshot) async throws -> URL
    func ensureRepositorySubscription(using descriptor: RepositoryDescriptor) async throws
    @MainActor
    func makeSharingController(
        using descriptor: RepositoryDescriptor,
        snapshot: RepositorySnapshot,
        access: ShareAccessOption
    ) async throws -> UICloudSharingController
    func acceptShare(from url: URL) async throws -> AcceptedSharedRepository
    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository
}

struct AcceptedSharedRepository: Sendable {
    var descriptor: RepositoryDescriptor
    var snapshot: RepositorySnapshot
    var displayName: String?
}

enum CloudRepositoryError: LocalizedError {
    case repositoryDescriptorMissing
    case shareLinkInvalid
    case repositoryNotFound
    case repositoryLocked
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
        static let sharedDatabaseSubscriptionID = "repository-updates-shared-database"
        static let updatedAtKey: CKRecord.FieldKey = "updatedAt"
        static let entryCountKey: CKRecord.FieldKey = "entryCount"
        static let payloadKey: CKRecord.FieldKey = "payload"
        static let referenceKey: CKRecord.FieldKey = "reference"
        static let contentHashKey: CKRecord.FieldKey = "contentHash"
        static let recordBatchSize = 50
    }

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
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
        return RepositorySnapshotMetadata(updatedAt: updatedAt, entryCount: entryCount)
    }

    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot {
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
        let referencedImages = Self.localImageReferences(in: snapshot)
        let embeddedReferences = Set(snapshot.embeddedImages.map(\.reference))
        let missingReferences = referencedImages.subtracting(embeddedReferences)

        guard !missingReferences.isEmpty else {
            return snapshot
        }

        let fetchedImages = try await fetchImageAssets(
            references: Array(missingReferences).sorted(),
            zoneID: zoneID,
            in: database
        )

        return RepositorySnapshot(
            entries: snapshot.entries,
            updatedAt: snapshot.updatedAt,
            embeddedImages: snapshot.embeddedImages + fetchedImages,
            blogTags: snapshot.blogTags,
            sharedUpdateNotificationScope: snapshot.sharedUpdateNotificationScope
        )
    }

    func saveSnapshot(_ snapshot: RepositorySnapshot, using descriptor: RepositoryDescriptor) async throws -> RepositoryDescriptor {
        guard descriptor.role.canEdit else {
            throw CloudRepositoryError.repositoryLocked
        }

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
        let record = try await fetchRecordIfPresent(
            recordID: recordID,
            in: database,
            desiredKeys: [Constant.updatedAtKey, Constant.entryCountKey]
        ) ?? CKRecord(recordType: Constant.recordType, recordID: recordID)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let archiveData = try encoder.encode(snapshot.removingEmbeddedImages())
        let temporaryFile = try TemporaryAssetFile(data: archiveData, fileExtension: "json")

        try await saveImageAssets(snapshot.embeddedImages, zoneID: zoneID, in: database)

        record[Constant.updatedAtKey] = snapshot.updatedAt as CKRecordValue
        record[Constant.entryCountKey] = snapshot.entries.count as CKRecordValue
        record[Constant.payloadKey] = CKAsset(fileURL: temporaryFile.url)

        _ = try await saveRecord(record, in: database)
        _ = temporaryFile

        if normalizedDescriptor.role == .owner,
           let share = try await fetchShareIfPresent(zoneID: zoneID, in: privateDatabase) {
            normalizedDescriptor.shareRecordName = share.recordID.recordName
        }

        return normalizedDescriptor
    }

    func shareURL(using descriptor: RepositoryDescriptor, snapshot: RepositorySnapshot) async throws -> URL {
        let normalizedDescriptor = try await saveSnapshot(snapshot, using: descriptor)
        guard normalizedDescriptor.role == .owner,
              let zoneID = normalizedDescriptor.zoneID else {
            throw CloudRepositoryError.shareUnavailable
        }

        let share = try await fetchOrCreateShare(zoneID: zoneID)
        guard let url = share.url else {
            throw CloudRepositoryError.shareUnavailable
        }

        return url
    }

    func ensureRepositorySubscription(using descriptor: RepositoryDescriptor) async throws {
        let subscription: CKSubscription
        let database: CKDatabase

        switch descriptor.role {
        case .local:
            return
        case .owner:
            guard let zoneID = descriptor.zoneID else {
                return
            }

            database = privateDatabase
            subscription = CKRecordZoneSubscription(
                zoneID: zoneID,
                subscriptionID: subscriptionID(for: descriptor)
            )
        case .editor, .viewer:
            database = sharedDatabase
            subscription = CKDatabaseSubscription(subscriptionID: Constant.sharedDatabaseSubscriptionID)
        }

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let result = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        switch result.saveResults[subscription.subscriptionID] {
        case .success:
            return
        case .failure(let error):
            throw error
        case nil:
            throw CloudRepositoryError.shareUnavailable
        }
    }

    @MainActor
    func makeSharingController(
        using descriptor: RepositoryDescriptor,
        snapshot: RepositorySnapshot,
        access: ShareAccessOption
    ) async throws -> UICloudSharingController {
        let normalizedDescriptor = try await saveSnapshot(snapshot, using: descriptor)
        guard normalizedDescriptor.role == .owner,
              let zoneID = normalizedDescriptor.zoneID else {
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
        let snapshot = try await loadSnapshot(using: descriptor)
        return AcceptedSharedRepository(
            descriptor: descriptor,
            snapshot: snapshot,
            displayName: L10n.sharedRepositoryDisplayName(ownerName: ownerDisplayName)
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
                desiredKeys: [Constant.referenceKey, Constant.payloadKey]
            )

            for reference in batch {
                guard let recordID = idsByReference[reference],
                      let result = results[recordID] else {
                    continue
                }

                switch result {
                case .success(let record):
                    let storedReference = (record[Constant.referenceKey] as? String) ?? reference
                    guard let asset = record[Constant.payloadKey] as? CKAsset,
                          let data = try Self.assetData(from: asset) else {
                        continue
                    }

                    assetsByReference[reference] = RepositoryImageAsset(reference: storedReference, data: data)
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        continue
                    }

                    throw error
                }
            }
        }

        return references.compactMap { assetsByReference[$0] }
    }

    private func saveImageAssets(
        _ assets: [RepositoryImageAsset],
        zoneID: CKRecordZone.ID,
        in database: CKDatabase
    ) async throws {
        guard !assets.isEmpty else {
            return
        }

        let uniqueAssets = Dictionary(assets.map { ($0.reference, $0) }) { _, latest in latest }

        for batch in Self.chunks(Array(uniqueAssets.keys).sorted(), size: Constant.recordBatchSize) {
            let recordIDsByReference = Dictionary(
                uniqueKeysWithValues: batch.map { reference in
                    (
                        reference,
                        CKRecord.ID(recordName: Self.imageRecordName(for: reference), zoneID: zoneID)
                    )
                }
            )
            let existingResults = try await database.records(
                for: Array(recordIDsByReference.values),
                desiredKeys: [Constant.contentHashKey]
            )

            var temporaryFiles: [TemporaryAssetFile] = []
            let recordsToSave: [CKRecord] = try batch.compactMap { reference in
                guard let asset = uniqueAssets[reference],
                      let recordID = recordIDsByReference[reference] else {
                    return nil
                }

                let contentHash = Self.contentHash(for: asset.data)
                let record: CKRecord

                if let existingResult = existingResults[recordID] {
                    switch existingResult {
                    case .success(let existingRecord):
                        if existingRecord[Constant.contentHashKey] as? String == contentHash {
                            return nil
                        }

                        record = existingRecord
                    case .failure(let error):
                        if let ckError = error as? CKError, ckError.code == .unknownItem {
                            record = CKRecord(recordType: Constant.imageRecordType, recordID: recordID)
                        } else {
                            throw error
                        }
                    }
                } else {
                    record = CKRecord(recordType: Constant.imageRecordType, recordID: recordID)
                }

                let temporaryFile = try TemporaryAssetFile(data: asset.data, fileExtension: "jpg")
                temporaryFiles.append(temporaryFile)
                record[Constant.referenceKey] = reference as CKRecordValue
                record[Constant.contentHashKey] = contentHash as CKRecordValue
                record[Constant.payloadKey] = CKAsset(fileURL: temporaryFile.url)
                return record
            }

            guard !recordsToSave.isEmpty else {
                continue
            }

            let result = try await database.modifyRecords(saving: recordsToSave, deleting: [])
            _ = temporaryFiles
            for record in recordsToSave {
                switch result.saveResults[record.recordID] {
                case .success:
                    continue
                case .failure(let error):
                    throw error
                case nil:
                    throw CloudRepositoryError.repositoryNotFound
                }
            }
        }
    }

    private func saveRecord(_ record: CKRecord, in database: CKDatabase) async throws -> CKRecord {
        let result = try await database.modifyRecords(saving: [record], deleting: [])
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

    private static func imageRecordName(for reference: String) -> String {
        "RepositoryImageAsset-\(reference)"
    }

    private static func contentHash(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func chunks<T>(_ values: [T], size: Int) -> [[T]] {
        guard size > 0 else {
            return [values]
        }

        return stride(from: 0, to: values.count, by: size).map { startIndex in
            Array(values[startIndex..<min(startIndex + size, values.count)])
        }
    }

    private static func localImageReferences(in snapshot: RepositorySnapshot) -> Set<String> {
        Set(snapshot.entries.compactMap { localImageReference($0.imageReference) })
    }

    private static func localImageReference(_ reference: String?) -> String? {
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

    private func subscriptionID(for descriptor: RepositoryDescriptor) -> String {
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
