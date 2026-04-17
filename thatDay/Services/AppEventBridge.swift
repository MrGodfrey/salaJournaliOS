import Combine
import Foundation
import UserNotifications

struct NotificationEntryRoute: Hashable, Sendable {
    var repositoryID: String
    var entryID: UUID?
}

@MainActor
final class RepositoryRemoteChangeCenter: ObservableObject {
    static let shared = RepositoryRemoteChangeCenter()

    @Published private(set) var deliverySequence = 0

    private var pendingUserInfos: [[AnyHashable: Any]] = []

    private init() {}

    func enqueue(_ userInfo: [AnyHashable: Any]) {
        pendingUserInfos.append(userInfo)
        deliverySequence &+= 1
    }

    func drainPendingUserInfos() -> [[AnyHashable: Any]] {
        defer { pendingUserInfos.removeAll() }
        return pendingUserInfos
    }
}

@MainActor
final class NotificationRouteCenter: ObservableObject {
    static let shared = NotificationRouteCenter()

    @Published private(set) var deliverySequence = 0

    private var pendingRoutes: [NotificationEntryRoute] = []

    private init() {}

    func enqueue(_ route: NotificationEntryRoute) {
        pendingRoutes.append(route)
        deliverySequence &+= 1
    }

    func drainPendingRoutes() -> [NotificationEntryRoute] {
        defer { pendingRoutes.removeAll() }
        return pendingRoutes
    }
}

enum LocalNotificationPayload {
    static let repositoryIDKey = "repositoryID"
    static let entryIDKey = "entryID"

    static func route(from userInfo: [AnyHashable: Any]) -> NotificationEntryRoute? {
        guard let repositoryID = (userInfo[repositoryIDKey] as? String)?.trimmed.nilIfEmpty else {
            return nil
        }

        let entryID = (userInfo[entryIDKey] as? String).flatMap(UUID.init(uuidString:))
        return NotificationEntryRoute(repositoryID: repositoryID, entryID: entryID)
    }

    static func route(from notification: UNNotification) -> NotificationEntryRoute? {
        route(from: notification.request.content.userInfo)
    }
}
