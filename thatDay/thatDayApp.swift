import CloudKit
import Combine
import SwiftUI
import UserNotifications

@main
struct thatDayApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: AppStore
    @StateObject private var cloudShareDeliveryCenter = CloudShareDeliveryCenter.shared
    @StateObject private var repositoryRemoteChangeCenter = RepositoryRemoteChangeCenter.shared
    @StateObject private var notificationRouteCenter = NotificationRouteCenter.shared

    init() {
        let processInfo = ProcessInfo.processInfo
        let libraryStore = RepositoryLibraryStore.live(processInfo: processInfo)

        if processInfo.environment["THATDAY_RESET_STORAGE"] == "1" {
            try? FileManager.default.removeItem(at: libraryStore.rootURL)
        }

        let referenceDate = AppStore.referenceDate(from: processInfo.environment)
        _store = State(
            initialValue: AppStore(
                libraryStore: libraryStore,
                cloudService: CloudRepositoryService(
                    containerIdentifier: processInfo.environment["THATDAY_CLOUDKIT_CONTAINER"] ?? "iCloud.yu.thatDay"
                ),
                now: { referenceDate ?? Date() }
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .environment(\.locale, AppLanguage.locale)
                .task(id: cloudShareDeliveryCenter.deliverySequence) {
                    for metadata in cloudShareDeliveryCenter.drainPendingMetadata() {
                        await store.acceptShare(metadata: metadata)
                    }
                }
                .task(id: repositoryRemoteChangeCenter.deliverySequence) {
                    let pendingUserInfos = repositoryRemoteChangeCenter.drainPendingUserInfos()
                    guard !pendingUserInfos.isEmpty else {
                        return
                    }

                    await store.refreshSharedRepositories(trigger: .push)
                }
                .task(id: notificationRouteCenter.deliverySequence) {
                    for route in notificationRouteCenter.drainPendingRoutes() {
                        await store.handleNotificationRoute(route)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    Task {
                        await store.handleScenePhaseChange(newPhase)
                        if newPhase == .active {
                            await store.refreshSharedRepositories(trigger: .foreground)
                        }
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = CloudShareSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        deliver(cloudKitShareMetadata)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            RepositoryRemoteChangeCenter.shared.enqueue(userInfo)
            completionHandler(.newData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let route = LocalNotificationPayload.route(from: response.notification) else {
            return
        }

        await MainActor.run {
            NotificationRouteCenter.shared.enqueue(route)
        }
    }

    private func deliver(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            CloudShareDeliveryCenter.shared.enqueue(metadata)
        }
    }
}

final class CloudShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else {
            return
        }

        deliver(metadata)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        deliver(cloudKitShareMetadata)
    }

    private func deliver(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            CloudShareDeliveryCenter.shared.enqueue(metadata)
        }
    }
}

@MainActor
final class CloudShareDeliveryCenter: ObservableObject {
    static let shared = CloudShareDeliveryCenter()

    @Published private(set) var deliverySequence = 0

    private var pendingMetadata: [CKShare.Metadata] = []
    private var pendingKeys: Set<String> = []

    private init() {}

    func enqueue(_ metadata: CKShare.Metadata) {
        let key = Self.makeKey(for: metadata)
        guard pendingKeys.insert(key).inserted else {
            return
        }

        pendingMetadata.append(metadata)
        deliverySequence &+= 1
    }

    func drainPendingMetadata() -> [CKShare.Metadata] {
        defer {
            pendingMetadata.removeAll()
            pendingKeys.removeAll()
        }

        return pendingMetadata
    }

    private nonisolated static func makeKey(for metadata: CKShare.Metadata) -> String {
        let recordID = metadata.share.recordID
        return "\(recordID.zoneID.ownerName):\(recordID.zoneID.zoneName):\(recordID.recordName)"
    }
}
