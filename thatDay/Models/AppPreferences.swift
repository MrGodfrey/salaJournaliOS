import Foundation

nonisolated enum AppTimeZone: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case beijing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            L10n.string("System Default")
        case .beijing:
            L10n.string("Beijing Time")
        }
    }

    func resolve(systemTimeZone: TimeZone) -> TimeZone {
        switch self {
        case .system:
            systemTimeZone
        case .beijing:
            TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 60 * 60) ?? systemTimeZone
        }
    }
}

nonisolated enum SharedUpdateNotificationScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case all
    case journal
    case blog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            L10n.string("All")
        case .journal:
            L10n.string("Journal")
        case .blog:
            L10n.string("Blog")
        }
    }

    var summary: String {
        switch self {
        case .all:
            L10n.string("Journal and Blog updates")
        case .journal:
            L10n.string("Journal updates")
        case .blog:
            L10n.string("Blog updates")
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
    var appTimeZone: AppTimeZone
    var cloudRetryAfter: Date?
    var lastSuccessfulCloudRefreshAt: Date?
    var cloudAccountUserRecordName: String?

    init(
        defaultRepositoryID: String = RepositoryReference.localRepositoryID,
        isBiometricLockEnabled: Bool = false,
        isSharedUpdateNotificationEnabled: Bool = false,
        sharedUpdateNotificationScope: SharedUpdateNotificationScope = .all,
        appTimeZone: AppTimeZone = .system,
        cloudRetryAfter: Date? = nil,
        lastSuccessfulCloudRefreshAt: Date? = nil,
        cloudAccountUserRecordName: String? = nil
    ) {
        self.defaultRepositoryID = defaultRepositoryID
        self.isBiometricLockEnabled = isBiometricLockEnabled
        self.isSharedUpdateNotificationEnabled = isSharedUpdateNotificationEnabled
        self.sharedUpdateNotificationScope = sharedUpdateNotificationScope
        self.appTimeZone = appTimeZone
        self.cloudRetryAfter = cloudRetryAfter
        self.lastSuccessfulCloudRefreshAt = lastSuccessfulCloudRefreshAt
        self.cloudAccountUserRecordName =
            cloudAccountUserRecordName
    }

    private enum CodingKeys: String, CodingKey {
        case defaultRepositoryID
        case isBiometricLockEnabled
        case isSharedUpdateNotificationEnabled
        case sharedUpdateNotificationScope
        case appTimeZone
        case cloudRetryAfter
        case lastSuccessfulCloudRefreshAt
        case cloudAccountUserRecordName
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultRepositoryID = try container.decodeIfPresent(String.self, forKey: .defaultRepositoryID)
            ?? RepositoryReference.localRepositoryID
        isBiometricLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .isBiometricLockEnabled) ?? false
        isSharedUpdateNotificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSharedUpdateNotificationEnabled) ?? false
        sharedUpdateNotificationScope = try container.decodeIfPresent(SharedUpdateNotificationScope.self, forKey: .sharedUpdateNotificationScope) ?? .all
        appTimeZone = try container.decodeIfPresent(AppTimeZone.self, forKey: .appTimeZone) ?? .system
        cloudRetryAfter = try container.decodeIfPresent(Date.self, forKey: .cloudRetryAfter)
        lastSuccessfulCloudRefreshAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulCloudRefreshAt)
        cloudAccountUserRecordName = try container.decodeIfPresent(
            String.self,
            forKey: .cloudAccountUserRecordName
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultRepositoryID, forKey: .defaultRepositoryID)
        try container.encode(isBiometricLockEnabled, forKey: .isBiometricLockEnabled)
        try container.encode(isSharedUpdateNotificationEnabled, forKey: .isSharedUpdateNotificationEnabled)
        try container.encode(sharedUpdateNotificationScope, forKey: .sharedUpdateNotificationScope)
        try container.encode(appTimeZone, forKey: .appTimeZone)
        try container.encodeIfPresent(cloudRetryAfter, forKey: .cloudRetryAfter)
        try container.encodeIfPresent(lastSuccessfulCloudRefreshAt, forKey: .lastSuccessfulCloudRefreshAt)
        try container.encodeIfPresent(
            cloudAccountUserRecordName,
            forKey: .cloudAccountUserRecordName
        )
    }
}
