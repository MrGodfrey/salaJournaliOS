import Foundation

nonisolated struct AppPreferences: Codable, Hashable, Sendable {
    var defaultRepositoryID: String = RepositoryReference.localRepositoryID
    var isBiometricLockEnabled = false
    var isSharedUpdateNotificationEnabled = false
}
