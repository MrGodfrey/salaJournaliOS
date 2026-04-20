import Foundation

nonisolated enum SharedUpdateNotificationScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case all
    case journal
    case blog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .journal:
            "Journal"
        case .blog:
            "Blog"
        }
    }

    var summary: String {
        switch self {
        case .all:
            "Journal and Blog updates"
        case .journal:
            "Journal updates"
        case .blog:
            "Blog updates"
        }
    }

    func includes(_ kind: EntryKind) -> Bool {
        switch self {
        case .all:
            true
        case .journal:
            kind == .journal
        case .blog:
            kind == .blog
        }
    }
}

nonisolated struct AppPreferences: Codable, Hashable, Sendable {
    var defaultRepositoryID: String
    var isBiometricLockEnabled: Bool
    var isSharedUpdateNotificationEnabled: Bool
    var sharedUpdateNotificationScope: SharedUpdateNotificationScope

    init(
        defaultRepositoryID: String = RepositoryReference.localRepositoryID,
        isBiometricLockEnabled: Bool = false,
        isSharedUpdateNotificationEnabled: Bool = false,
        sharedUpdateNotificationScope: SharedUpdateNotificationScope = .all
    ) {
        self.defaultRepositoryID = defaultRepositoryID
        self.isBiometricLockEnabled = isBiometricLockEnabled
        self.isSharedUpdateNotificationEnabled = isSharedUpdateNotificationEnabled
        self.sharedUpdateNotificationScope = sharedUpdateNotificationScope
    }

    private enum CodingKeys: String, CodingKey {
        case defaultRepositoryID
        case isBiometricLockEnabled
        case isSharedUpdateNotificationEnabled
        case sharedUpdateNotificationScope
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultRepositoryID = try container.decodeIfPresent(String.self, forKey: .defaultRepositoryID)
            ?? RepositoryReference.localRepositoryID
        isBiometricLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .isBiometricLockEnabled) ?? false
        isSharedUpdateNotificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSharedUpdateNotificationEnabled) ?? false
        sharedUpdateNotificationScope = try container.decodeIfPresent(SharedUpdateNotificationScope.self, forKey: .sharedUpdateNotificationScope) ?? .all
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultRepositoryID, forKey: .defaultRepositoryID)
        try container.encode(isBiometricLockEnabled, forKey: .isBiometricLockEnabled)
        try container.encode(isSharedUpdateNotificationEnabled, forKey: .isSharedUpdateNotificationEnabled)
        try container.encode(sharedUpdateNotificationScope, forKey: .sharedUpdateNotificationScope)
    }
}
