import CloudKit
import Combine
import Foundation
import OSLog
import UIKit
import UserNotifications

nonisolated enum SyncDiagnostics {
    static let logger = Logger(
        subsystem: "yu.thatDay",
        category: "CloudSync"
    )
}

struct NotificationEntryRoute: Hashable, Sendable {
    var repositoryID: String
    var entryID: UUID?
}

nonisolated enum CloudDatabaseScope: Equatable, Hashable, Sendable {
    case privateDatabase
    case sharedDatabase

    init?(_ scope: CKDatabase.Scope) {
        switch scope {
        case .private:
            self = .privateDatabase
        case .shared:
            self = .sharedDatabase
        case .public:
            return nil
        @unknown default:
            return nil
        }
    }
}

nonisolated enum CloudRemoteNotificationTarget: Equatable, Sendable {
    case database(CloudDatabaseScope)
    case zone(ownerName: String, zoneName: String)

    init?(remoteNotificationDictionary userInfo: [AnyHashable: Any]) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return nil
        }

        if let zoneNotification = notification as? CKRecordZoneNotification {
            if let zoneID = zoneNotification.recordZoneID {
                self = .zone(ownerName: zoneID.ownerName, zoneName: zoneID.zoneName)
                return
            }

            guard let scope = CloudDatabaseScope(zoneNotification.databaseScope) else {
                return nil
            }
            self = .database(scope)
            return
        }

        if let databaseNotification = notification as? CKDatabaseNotification,
           let scope = CloudDatabaseScope(databaseNotification.databaseScope) {
            self = .database(scope)
            return
        }

        return nil
    }
}

@MainActor
final class RepositoryRemoteChangeCenter {
    typealias Handler = (CloudRemoteNotificationTarget?) async -> UIBackgroundFetchResult

    static let shared = RepositoryRemoteChangeCenter()

    private var handler: Handler?

    init() {}

    func installHandler(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func processRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard let target = CloudRemoteNotificationTarget(
            remoteNotificationDictionary: userInfo
        ) else {
            SyncDiagnostics.logger.notice(
                "Ignored a remote notification that was not a supported CloudKit database or zone notification."
            )
            return .noData
        }
        guard let handler else {
            SyncDiagnostics.logger.error(
                "Received a CloudKit notification before the repository sync handler was installed."
            )
            return .failed
        }

        let result = await handler(target)
        SyncDiagnostics.logger.info(
            "Finished CloudKit push processing with background result \(result.rawValue, privacy: .public)."
        )
        return result
    }

    func performRecoveryRefresh() async -> UIBackgroundFetchResult {
        guard let handler else {
            SyncDiagnostics.logger.error(
                "Background recovery ran before the repository sync handler was installed."
            )
            return .failed
        }

        let result = await handler(nil)
        SyncDiagnostics.logger.info(
            "Finished scheduled CloudKit recovery with background result \(result.rawValue, privacy: .public)."
        )
        return result
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
