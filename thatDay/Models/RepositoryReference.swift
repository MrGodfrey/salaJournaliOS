import Foundation

nonisolated enum RepositorySource: String, Codable, Hashable, Sendable {
    case local
    case shared
}

nonisolated struct RepositoryReference: Identifiable, Codable, Hashable, Sendable {
    static let localRepositoryID = "local"

    var id: String
    var displayName: String
    var descriptor: RepositoryDescriptor
    var source: RepositorySource
    var lastKnownSnapshotUpdatedAt: Date?
    var subscribedAt: Date
    var lastOpenedAt: Date?
    var lastKnownServerRecordChangeTag: String?
    var lastKnownServerModifiedAt: Date?
    var pendingCloudUploadAt: Date?
    var pendingCloudUploadGeneration: Int?
    var pendingCloudUploadBaseChangeTag: String?
    var cloudUploadConflictServerChangeTag: String?
    var cloudUploadConflictDetectedAt: Date?
    var cloudZoneUnavailableAt: Date?
    var cloudPurgeRequestedAt: Date?
    var subscriptionConfigurationVersion: Int?
    var subscriptionValidatedAt: Date?

    init(
        id: String,
        displayName: String,
        descriptor: RepositoryDescriptor,
        source: RepositorySource,
        lastKnownSnapshotUpdatedAt: Date? = nil,
        subscribedAt: Date = .now,
        lastOpenedAt: Date? = nil,
        lastKnownServerRecordChangeTag: String? = nil,
        lastKnownServerModifiedAt: Date? = nil,
        pendingCloudUploadAt: Date? = nil,
        pendingCloudUploadGeneration: Int? = nil,
        pendingCloudUploadBaseChangeTag: String? = nil,
        cloudUploadConflictServerChangeTag: String? = nil,
        cloudUploadConflictDetectedAt: Date? = nil,
        cloudZoneUnavailableAt: Date? = nil,
        cloudPurgeRequestedAt: Date? = nil,
        subscriptionConfigurationVersion: Int? = nil,
        subscriptionValidatedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.descriptor = descriptor
        self.source = source
        self.lastKnownSnapshotUpdatedAt = lastKnownSnapshotUpdatedAt
        self.subscribedAt = subscribedAt
        self.lastOpenedAt = lastOpenedAt
        self.lastKnownServerRecordChangeTag = lastKnownServerRecordChangeTag
        self.lastKnownServerModifiedAt = lastKnownServerModifiedAt
        self.pendingCloudUploadAt = pendingCloudUploadAt
        self.pendingCloudUploadGeneration = pendingCloudUploadGeneration
        self.pendingCloudUploadBaseChangeTag = pendingCloudUploadBaseChangeTag
        self.cloudUploadConflictServerChangeTag = cloudUploadConflictServerChangeTag
        self.cloudUploadConflictDetectedAt = cloudUploadConflictDetectedAt
        self.cloudZoneUnavailableAt = cloudZoneUnavailableAt
        self.cloudPurgeRequestedAt = cloudPurgeRequestedAt
        self.subscriptionConfigurationVersion = subscriptionConfigurationVersion
        self.subscriptionValidatedAt = subscriptionValidatedAt
    }

    static let local = RepositoryReference(
        id: localRepositoryID,
        displayName: "My Repository",
        descriptor: .local,
        source: .local
    )

    var isLocal: Bool {
        source == .local
    }

    var localizedDisplayName: String {
        L10n.localizedRepositoryDisplayName(displayName, descriptor: descriptor, source: source)
    }
}
