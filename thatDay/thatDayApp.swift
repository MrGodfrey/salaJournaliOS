import CloudKit
import Combine
import SwiftUI

@main
struct thatDayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: AppStore
    @StateObject private var cloudShareDeliveryCenter = CloudShareDeliveryCenter.shared

    init() {
        let processInfo = ProcessInfo.processInfo
        let repositoryStore = LocalRepositoryStore.live(processInfo: processInfo)

        if processInfo.environment["THATDAY_RESET_STORAGE"] == "1" {
            try? repositoryStore.reset()
        }

        let referenceDate = AppStore.referenceDate(from: processInfo.environment)
        _store = State(
            initialValue: AppStore(
                repositoryStore: repositoryStore,
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
                .task(id: cloudShareDeliveryCenter.deliverySequence) {
                    for metadata in cloudShareDeliveryCenter.drainPendingMetadata() {
                        await store.acceptShare(metadata: metadata)
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
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
