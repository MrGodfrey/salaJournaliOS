import CloudKit
import UIKit
import XCTest
@testable import thatDay

final class ImageReplacementDurabilityTests: AppStoreTestCase {
    @MainActor
    func testReplacingImageUsesNewReferenceAndOnlyPrunesOldImageAfterOutboxIsDurable() async throws {
        let fixture = try await makeCloudFixture()
        fixture.cloudService.pauseSaveSnapshot = true
        let uploadStarted = expectation(description: "replacement upload started")
        let uploadFinished = expectation(description: "replacement upload finished")
        fixture.cloudService.saveSnapshotStartedExpectation = uploadStarted
        fixture.cloudService.saveSnapshotFinishedExpectation = uploadFinished

        let didSave = await fixture.appStore.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "Replaced image",
                body: fixture.entry.body,
                happenedAt: fixture.entry.happenedAt
            ),
            importedImageData: try XCTUnwrap(makeLargeImageData()),
            editing: fixture.entry
        )

        XCTAssertTrue(didSave)
        let updatedEntry = try XCTUnwrap(fixture.appStore.entries.first)
        let updatedReference = try XCTUnwrap(updatedEntry.imageReference)
        XCTAssertNotEqual(updatedReference, fixture.oldImageReference)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(fixture.repositoryStore.imageURL(for: updatedReference)).path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.oldImageURL.path))

        let durableOutbox = try XCTUnwrap(fixture.outboxStore.load())
        XCTAssertEqual(durableOutbox.snapshot.entries.first?.imageReference, updatedReference)
        XCTAssertEqual(durableOutbox.snapshot.embeddedImages.map(\.reference), [updatedReference])
        XCTAssertEqual(
            durableOutbox.snapshot.embeddedImages.first?.data,
            try Data(contentsOf: XCTUnwrap(fixture.repositoryStore.imageURL(for: updatedReference)))
        )
        XCTAssertEqual(
            try fixture.repositoryStore.loadSnapshot()?.entries.first?.imageReference,
            updatedReference
        )

        await fulfillment(of: [uploadStarted], timeout: 1)
        fixture.cloudService.resumePausedSaveSnapshot()
        await fulfillment(of: [uploadFinished], timeout: 1)
    }

    @MainActor
    func testOutboxFailureRollsBackStagedReplacementAndPreservesOldSnapshotAndImage() async throws {
        let fixture = try await makeCloudFixture()
        try FileManager.default.createDirectory(
            at: fixture.outboxStore.fileURL,
            withIntermediateDirectories: true
        )

        let didSave = await fixture.appStore.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "This edit must roll back",
                body: fixture.entry.body,
                happenedAt: fixture.entry.happenedAt
            ),
            importedImageData: try XCTUnwrap(makeLargeImageData()),
            editing: fixture.entry
        )

        XCTAssertFalse(didSave)
        XCTAssertEqual(fixture.appStore.entries, [fixture.entry])
        XCTAssertEqual(try fixture.repositoryStore.loadSnapshot(), fixture.snapshot)
        XCTAssertEqual(
            try Data(contentsOf: fixture.oldImageURL),
            fixture.oldImageData
        )

        let remainingImageReferences = try FileManager.default
            .contentsOfDirectory(
                at: fixture.repositoryStore.imagesURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .map(\.lastPathComponent)
        XCTAssertEqual(remainingImageReferences, [fixture.oldImageReference])
        XCTAssertTrue(fixture.cloudService.savedSnapshots.isEmpty)
    }

    @MainActor
    func testCreatingEntryWithImageStillPersistsItsGeneratedReference() async throws {
        let now = fixtureDate("2026-07-22T12:00:00Z")
        let rootURL = makeTempDirectory()
        let appStore = try makeStore(now: now, entries: [], rootURL: rootURL)
        await appStore.loadIfNeeded()

        let didSave = await appStore.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "New entry with image",
                body: "The create path keeps its image.",
                happenedAt: now
            ),
            importedImageData: try XCTUnwrap(makePreviewImageData())
        )

        XCTAssertTrue(didSave)
        let entry = try XCTUnwrap(appStore.entries.first)
        let imageReference = try XCTUnwrap(entry.imageReference)
        let repositoryStore = RepositoryLibraryStore(rootURL: rootURL)
            .repositoryStore(for: RepositoryReference.localRepositoryID)
        XCTAssertNotNil(repositoryStore.imageURL(for: imageReference))
        XCTAssertEqual(
            try repositoryStore.loadSnapshot()?.entries.first?.imageReference,
            imageReference
        )
    }

    @MainActor
    private func makeCloudFixture() async throws -> CloudImageFixture {
        let rootURL = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: rootURL)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let timestamp = fixtureDate("2026-07-22T10:00:00Z")
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(RepositorySnapshot(entries: [], updatedAt: timestamp))

        let descriptor = RepositoryDescriptor(
            zoneName: "image-replacement-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: "image-replacement-share",
            role: .owner
        )
        let repositoryID = descriptor.storageIdentifier
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let entryID = UUID()
        let oldImageReference = try repositoryStore.storeImage(
            data: try XCTUnwrap(makePreviewImageData()),
            suggestedID: entryID
        )
        let oldImageURL = try XCTUnwrap(repositoryStore.imageURL(for: oldImageReference))
        let oldImageData = try Data(contentsOf: oldImageURL)
        let entry = EntryRecord(
            id: entryID,
            kind: .journal,
            title: "Original image",
            body: "Keep this snapshot intact until replacement is durable.",
            happenedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp,
            imageReference: oldImageReference
        )
        let snapshot = RepositorySnapshot(entries: [entry], updatedAt: timestamp)
        try repositoryStore.saveDescriptor(descriptor)
        try repositoryStore.saveSnapshot(snapshot)

        let reference = RepositoryReference(
            id: repositoryID,
            displayName: "Image Replacement Repository",
            descriptor: descriptor,
            source: .shared,
            lastKnownSnapshotUpdatedAt: timestamp,
            lastKnownServerRecordChangeTag: "image-baseline-tag"
        )
        try libraryStore.saveCatalog([.local, reference])
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: repositoryID,
                isBiometricLockEnabled: false,
                isSharedUpdateNotificationEnabled: false
            )
        )

        let cloudService = MockCloudRepositoryService()
        cloudService.loadedSnapshot = snapshot
        cloudService.metadataRecordChangeTag = "image-baseline-tag"
        let appStore = AppStore(
            libraryStore: libraryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-07-22T11:00:00Z") }
        )
        await appStore.loadIfNeeded()

        return CloudImageFixture(
            appStore: appStore,
            cloudService: cloudService,
            repositoryStore: repositoryStore,
            outboxStore: CloudUploadOutboxStore(
                repositoryRootURL: repositoryStore.rootURL
            ),
            entry: entry,
            snapshot: snapshot,
            oldImageReference: oldImageReference,
            oldImageURL: oldImageURL,
            oldImageData: oldImageData
        )
    }
}

@MainActor
private struct CloudImageFixture {
    let appStore: AppStore
    let cloudService: MockCloudRepositoryService
    let repositoryStore: LocalRepositoryStore
    let outboxStore: CloudUploadOutboxStore
    let entry: EntryRecord
    let snapshot: RepositorySnapshot
    let oldImageReference: String
    let oldImageURL: URL
    let oldImageData: Data
}
