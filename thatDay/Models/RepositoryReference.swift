import Foundation

enum RepositorySource: String, Codable, Hashable, Sendable {
    case local
    case shared
}

struct RepositoryReference: Identifiable, Codable, Hashable, Sendable {
    static let localRepositoryID = "local"

    var id: String
    var displayName: String
    var descriptor: RepositoryDescriptor
    var source: RepositorySource
    var lastKnownSnapshotUpdatedAt: Date?
    var subscribedAt: Date
    var lastOpenedAt: Date?

    init(
        id: String,
        displayName: String,
        descriptor: RepositoryDescriptor,
        source: RepositorySource,
        lastKnownSnapshotUpdatedAt: Date? = nil,
        subscribedAt: Date = .now,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.descriptor = descriptor
        self.source = source
        self.lastKnownSnapshotUpdatedAt = lastKnownSnapshotUpdatedAt
        self.subscribedAt = subscribedAt
        self.lastOpenedAt = lastOpenedAt
    }

    static let local = RepositoryReference(
        id: localRepositoryID,
        displayName: "我的仓库",
        descriptor: .local,
        source: .local
    )

    var isLocal: Bool {
        source == .local
    }
}
