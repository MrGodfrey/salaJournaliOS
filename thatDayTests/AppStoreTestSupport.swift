import CloudKit
import ObjectiveC.runtime
import UIKit
import XCTest
@testable import thatDay

class AppStoreTestCase: XCTestCase {
    @MainActor
    func makeStore(
        now: Date,
        entries: [EntryRecord]? = nil,
        blogTags: [String] = RepositorySnapshot.defaultBlogTags,
        rootURL: URL? = nil,
        cloudService: any CloudRepositoryServicing = MockCloudRepositoryService(),
        preferences: AppPreferences? = nil,
        authenticateBiometrics: @escaping (String) async throws -> Void = { _ in },
        setApplicationBadgeCount: @escaping (Int) -> Void = { _ in }
    ) throws -> AppStore {
        let libraryRoot = rootURL ?? makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: libraryRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)

        try localStore.saveDescriptor(.local)
        if let entries {
            try localStore.saveSnapshot(
                RepositorySnapshot(
                    entries: entries,
                    updatedAt: now,
                    blogTags: blogTags
                )
            )
        }
        if let preferences {
            try libraryStore.savePreferences(preferences)
        }

        return AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { now },
            authenticateBiometrics: authenticateBiometrics,
            setApplicationBadgeCount: setApplicationBadgeCount
        )
    }

    func makeEntry(
        kind: EntryKind = .journal,
        title: String,
        body: String = "Body",
        blogTag: String? = nil,
        blogImageLayout: BlogCardImageLayout = .landscape,
        happenedAt: Date
    ) -> EntryRecord {
        EntryRecord(
            kind: kind,
            title: title,
            body: body,
            blogTag: blogTag,
            blogImageLayout: blogImageLayout,
            happenedAt: happenedAt,
            createdAt: happenedAt,
            updatedAt: happenedAt
        )
    }

    func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeSymlinkedTempDirectory() throws -> URL {
        let containerURL = makeTempDirectory()
        let targetURL = containerURL.appendingPathComponent("real-root", isDirectory: true)
        let symlinkURL = containerURL.appendingPathComponent("tmp", isDirectory: true)

        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

        return symlinkURL
    }

    func makePreviewImageData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200))
        let image = renderer.image { context in
            context.cgContext.setFillColor(UIColor.systemIndigo.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(x: 24, y: 24, width: 272, height: 152))
        }
        return image.pngData()
    }

    func makeLargeImageData() -> Data? {
        let side = 2200
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            for row in stride(from: 0, to: side, by: 40) {
                for column in stride(from: 0, to: side, by: 40) {
                    let red = CGFloat((row / 40) % 11) / 10
                    let green = CGFloat((column / 40) % 13) / 12
                    let blue = CGFloat(((row + column) / 40) % 17) / 16
                    context.cgContext.setFillColor(UIColor(red: red, green: green, blue: blue, alpha: 1).cgColor)
                    context.cgContext.fill(CGRect(x: column, y: row, width: 40, height: 40))
                }
            }
        }
        return image.pngData()
    }

    func fixtureDate(_ rawValue: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue) ?? .now
    }

    func words(_ count: Int) -> String {
        Array(repeating: "word", count: count).joined(separator: " ")
    }

    func makeShareMetadata() throws -> CKShare.Metadata {
        let instance = try XCTUnwrap(class_createInstance(CKShare.Metadata.self, 0)) as AnyObject
        return unsafeDowncast(instance, to: CKShare.Metadata.self)
    }
}

final class MockCloudRepositoryService: CloudRepositoryServicing {
    var loadedSnapshot: RepositorySnapshot?
    var acceptedSharedRepository: AcceptedSharedRepository?
    var savedSnapshots: [RepositorySnapshot] = []
    var loadedDescriptors: [RepositoryDescriptor] = []
    var ensuredSubscriptionDescriptors: [RepositoryDescriptor] = []
    var acceptedShareURLs: [URL] = []
    var acceptedShareMetadataCount = 0
    var saveSnapshotStartedExpectation: XCTestExpectation?
    var pauseSaveSnapshot = false

    private var saveSnapshotContinuation: CheckedContinuation<Void, Never>?

    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot {
        loadedDescriptors.append(descriptor)

        if let loadedSnapshot {
            return loadedSnapshot
        }

        throw CloudRepositoryError.repositoryNotFound
    }

    func saveSnapshot(_ snapshot: RepositorySnapshot, using descriptor: RepositoryDescriptor) async throws -> RepositoryDescriptor {
        savedSnapshots.append(snapshot)

        if pauseSaveSnapshot {
            await withCheckedContinuation { continuation in
                saveSnapshotContinuation = continuation
                saveSnapshotStartedExpectation?.fulfill()
            }
        } else {
            saveSnapshotStartedExpectation?.fulfill()
        }

        if descriptor.role == .local {
            return RepositoryDescriptor(
                zoneName: "mock-zone",
                zoneOwnerName: CKCurrentUserDefaultName,
                shareRecordName: "mock-share",
                role: .owner
            )
        }

        return descriptor
    }

    func resumePausedSaveSnapshot() {
        saveSnapshotContinuation?.resume()
        saveSnapshotContinuation = nil
        pauseSaveSnapshot = false
    }

    func shareURL(using descriptor: RepositoryDescriptor, snapshot: RepositorySnapshot) async throws -> URL {
        URL(string: "https://www.icloud.com/share/mock-share")!
    }

    func ensureRepositorySubscription(using descriptor: RepositoryDescriptor) async throws {
        ensuredSubscriptionDescriptors.append(descriptor)
    }

    @MainActor
    func makeSharingController(
        using descriptor: RepositoryDescriptor,
        snapshot: RepositorySnapshot,
        access: ShareAccessOption
    ) async throws -> UICloudSharingController {
        UICloudSharingController(
            share: CKShare(recordZoneID: CKRecordZone.ID(zoneName: "mock-zone", ownerName: CKCurrentUserDefaultName)),
            container: CKContainer(identifier: "iCloud.yu.thatDay")
        )
    }

    func acceptShare(from url: URL) async throws -> AcceptedSharedRepository {
        acceptedShareURLs.append(url)

        if let acceptedSharedRepository {
            return acceptedSharedRepository
        }

        throw CloudRepositoryError.shareLinkInvalid
    }

    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository {
        acceptedShareMetadataCount += 1

        if let acceptedSharedRepository {
            return acceptedSharedRepository
        }

        throw CloudRepositoryError.shareLinkInvalid
    }
}

final class MockBiometricAuthenticator {
    private(set) var reasons: [String] = []
    var results: [Result<Void, Error>] = []

    func authenticate(reason: String) async throws {
        reasons.append(reason)

        guard !results.isEmpty else {
            return
        }

        switch results.removeFirst() {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}
