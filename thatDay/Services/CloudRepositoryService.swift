import CloudKit
import Foundation
import UIKit

protocol CloudRepositoryServicing {
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
            "The current repository is not connected to CloudKit yet."
        case .shareLinkInvalid:
            "Enter a valid iCloud share link."
        case .repositoryNotFound:
            "No data was found for the current shared repository."
        case .repositoryLocked:
            "The current shared repository is read-only and cannot be changed."
        case .invalidRepositoryData:
            "The repository data in CloudKit could not be recognized."
        case .shareUnavailable:
            "A share invite cannot be created right now. Confirm that iCloud and CloudKit are configured."
        }
    }
}

final class CloudRepositoryService: CloudRepositoryServicing {
    private enum Constant {
        static let zoneName = "thatday-repository"
        static let rootRecordName = "RepositoryRoot"
        static let recordType = "RepositoryRoot"
        static let sharedDatabaseSubscriptionID = "repository-updates-shared-database"
    }

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
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

        guard let asset = record["payload"] as? CKAsset,
              let data = try Self.assetData(from: asset) else {
            throw CloudRepositoryError.invalidRepositoryData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RepositorySnapshot.self, from: data)
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
        let record = try await fetchRecordIfPresent(recordID: recordID, in: database) ?? CKRecord(recordType: Constant.recordType, recordID: recordID)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let archiveData = try encoder.encode(snapshot)
        let temporaryFile = try TemporaryAssetFile(data: archiveData, fileExtension: "json")

        record["updatedAt"] = snapshot.updatedAt as CKRecordValue
        record["entryCount"] = snapshot.entries.count as CKRecordValue
        record["payload"] = CKAsset(fileURL: temporaryFile.url)

        _ = try await saveRecord(record, in: database)

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
            displayName: ownerDisplayName.map { "\($0)'s Shared Repository" } ?? descriptor.defaultDisplayName
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
        share[CKShare.SystemFieldKey.title] = "thatDay Repository" as CKRecordValue
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

    private func fetchRecordIfPresent(recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
        let results = try await database.records(for: [recordID])
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
