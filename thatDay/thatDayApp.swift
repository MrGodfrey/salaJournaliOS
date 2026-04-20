import CloudKit
import Combine
import SwiftUI
import UIKit
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
        if let seedScenario = processInfo.uiTestSeedScenario {
            try? seedScenario.prepare(in: libraryStore)
        }

        let referenceDate = AppStore.referenceDate(from: processInfo.environment)
        _store = State(
            initialValue: AppStore(
                libraryStore: libraryStore,
                cloudService: CloudRepositoryService(
                    containerIdentifier: processInfo.environment["THATDAY_CLOUDKIT_CONTAINER"] ?? "iCloud.yu.thatDay"
                ),
                now: { referenceDate ?? Date() },
                setApplicationBadgeCount: processInfo.isRunningUITests ? { _ in } : { badgeCount in
                    UNUserNotificationCenter.current().setBadgeCount(badgeCount) { _ in }
                }
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
        if !ProcessInfo.processInfo.isRunningUITests {
            application.registerForRemoteNotifications()
        }
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

private extension ProcessInfo {
    var isRunningUITests: Bool {
        environment["THATDAY_UI_TEST_MODE"] == "1"
    }

    var uiTestSeedScenario: UITestSeedScenario? {
        guard let rawValue = environment["THATDAY_UI_TEST_SEED"]?.trimmed.nilIfEmpty else {
            return nil
        }

        return UITestSeedScenario(rawValue: rawValue)
    }
}

private enum UITestSeedScenario: String {
    case taggedBlog = "tagged-blog"
    case portraitBlog = "portrait-blog"
    case readOnlyRepository = "read-only-repository"

    func prepare(in libraryStore: RepositoryLibraryStore) throws {
        switch self {
        case .taggedBlog:
            try prepareTaggedBlogRepository(in: libraryStore)
        case .portraitBlog:
            try preparePortraitBlogRepository(in: libraryStore)
        case .readOnlyRepository:
            try prepareReadOnlyRepository(in: libraryStore)
        }
    }

    private func prepareTaggedBlogRepository(in libraryStore: RepositoryLibraryStore) throws {
        let repositoryStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let happenedAt = Self.fixtureDate("2026-04-16T09:00:00Z")

        try repositoryStore.saveDescriptor(.local)
        try repositoryStore.saveSnapshot(
            RepositorySnapshot(
                entries: [
                    EntryRecord(
                        id: UUID(uuidString: "6B1F9BC2-9037-4B9F-8FE8-B85AE6FC0FA0") ?? UUID(),
                        kind: .blog,
                        title: "Reading Summary",
                        body: "A reading note.",
                        blogTag: "Reading",
                        happenedAt: happenedAt,
                        createdAt: happenedAt,
                        updatedAt: happenedAt
                    ),
                    EntryRecord(
                        id: UUID(uuidString: "6B1F9BC2-9037-4B9F-8FE8-B85AE6FC0FA1") ?? UUID(),
                        kind: .blog,
                        title: "Trip Recap",
                        body: "A trip note.",
                        blogTag: "Trip",
                        happenedAt: happenedAt,
                        createdAt: happenedAt,
                        updatedAt: happenedAt
                    )
                ],
                updatedAt: happenedAt,
                blogTags: ["Reading", "Trip", "note"]
            )
        )
        try libraryStore.savePreferences(AppPreferences())
    }

    private func preparePortraitBlogRepository(in libraryStore: RepositoryLibraryStore) throws {
        let repositoryStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let happenedAt = Self.fixtureDate("2026-04-16T09:00:00Z")
        let entryID = UUID(uuidString: "7BFC7E5E-EBB3-46D0-B2D0-A9CE4B63B8B2") ?? UUID()
        let imageReference = try repositoryStore.storeImage(data: Self.makePortraitSeedImageData(), suggestedID: entryID)

        try repositoryStore.saveDescriptor(.local)
        try repositoryStore.saveSnapshot(
            RepositorySnapshot(
                entries: [
                    EntryRecord(
                        id: entryID,
                        kind: .blog,
                        title: "Interstellar (2014)",
                        body: "A profound exploration of love and gravity, Nolan folds intimacy into cosmic scale.",
                        blogTag: "Watching",
                        blogImageLayout: .portrait,
                        happenedAt: happenedAt,
                        createdAt: happenedAt,
                        updatedAt: happenedAt,
                        imageReference: imageReference
                    )
                ],
                updatedAt: happenedAt,
                blogTags: ["Watching", "note"]
            )
        )
        try libraryStore.savePreferences(AppPreferences())
    }

    private func prepareReadOnlyRepository(in libraryStore: RepositoryLibraryStore) throws {
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let repositoryID = "read-only-repository"
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let happenedAt = Self.fixtureDate("2026-04-16T09:00:00Z")
        let descriptor = RepositoryDescriptor(zoneName: nil, zoneOwnerName: nil, shareRecordName: nil, role: .viewer)

        try localStore.saveDescriptor(.local)
        try repositoryStore.saveDescriptor(descriptor)
        try repositoryStore.saveSnapshot(
            RepositorySnapshot(
                entries: [
                    EntryRecord(
                        id: UUID(uuidString: "2B1F9BC2-9037-4B9F-8FE8-B85AE6FC0FA0") ?? UUID(),
                        kind: .journal,
                        title: "Read-Only Journal",
                        body: "This repository should hide create actions.",
                        happenedAt: happenedAt,
                        createdAt: happenedAt,
                        updatedAt: happenedAt
                    ),
                    EntryRecord(
                        id: UUID(uuidString: "2B1F9BC2-9037-4B9F-8FE8-B85AE6FC0FA1") ?? UUID(),
                        kind: .blog,
                        title: "Read-Only Blog",
                        body: "Blog creation should also be hidden.",
                        happenedAt: happenedAt,
                        createdAt: happenedAt,
                        updatedAt: happenedAt
                    )
                ],
                updatedAt: happenedAt
            )
        )
        try libraryStore.saveCatalog([
            RepositoryReference.local,
            RepositoryReference(
                id: repositoryID,
                displayName: "Read-Only Repository",
                descriptor: descriptor,
                source: .shared,
                lastKnownSnapshotUpdatedAt: happenedAt,
                subscribedAt: happenedAt
            )
        ])
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )
    }

    private static func fixtureDate(_ rawValue: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue) ?? .now
    }

    private static func makePortraitSeedImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 420))
        let image = renderer.image { context in
            UIColor(red: 0.08, green: 0.12, blue: 0.23, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 420))

            UIColor(red: 0.71, green: 0.82, blue: 0.96, alpha: 1).setFill()
            context.fill(CGRect(x: 24, y: 28, width: 192, height: 192))

            UIColor.white.withAlphaComponent(0.8).setFill()
            context.fill(CGRect(x: 34, y: 250, width: 172, height: 20))
            context.fill(CGRect(x: 34, y: 286, width: 140, height: 16))
            context.fill(CGRect(x: 34, y: 316, width: 120, height: 16))
        }

        return image.pngData() ?? Data()
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
