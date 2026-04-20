import LocalAuthentication
import SwiftUI
import XCTest
@testable import thatDay

final class BiometricTests: AppStoreTestCase {
    @MainActor
    func testBiometricLockAuthenticatesOnLaunchAndOnlyReauthenticatesAfterBackground() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(
            RepositorySnapshot(
                entries: [makeEntry(title: "Protected Entry", happenedAt: now)],
                updatedAt: now
            )
        )
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: true,
                isSharedUpdateNotificationEnabled: false
            )
        )

        let biometricAuthenticator = MockBiometricAuthenticator()
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now },
            authenticateBiometrics: biometricAuthenticator.authenticate
        )

        await store.loadIfNeeded()
        XCTAssertEqual(biometricAuthenticator.reasons, ["Unlock thatDay"])
        XCTAssertFalse(store.isAuthenticationRequired)

        await store.handleScenePhaseChange(.active)
        XCTAssertEqual(biometricAuthenticator.reasons.count, 1)
        XCTAssertFalse(store.isAuthenticationRequired)

        await store.handleScenePhaseChange(.background)
        XCTAssertTrue(store.isAuthenticationRequired)

        await store.handleScenePhaseChange(.active)
        XCTAssertEqual(biometricAuthenticator.reasons, ["Unlock thatDay", "Unlock thatDay"])
        XCTAssertFalse(store.isAuthenticationRequired)
    }

    @MainActor
    func testSetBiometricLockEnabledPersistsPreference() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await store.loadIfNeeded()

        store.setBiometricLockEnabled(true)

        XCTAssertTrue(store.isBiometricLockEnabled)
        XCTAssertTrue(try libraryStore.loadPreferences().isBiometricLockEnabled)
    }

    @MainActor
    func testUnlockIfNeededShowsAlertOnAuthenticationFailure() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(RepositorySnapshot(entries: [], updatedAt: now))
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: true,
                isSharedUpdateNotificationEnabled: false
            )
        )

        let biometricAuthenticator = MockBiometricAuthenticator()
        biometricAuthenticator.results = [
            .success(()),
            .failure(StubLocalizedError(message: "Face ID failed"))
        ]
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now },
            authenticateBiometrics: biometricAuthenticator.authenticate
        )

        await store.loadIfNeeded()
        await store.handleScenePhaseChange(.background)
        await store.handleScenePhaseChange(.active)

        XCTAssertEqual(store.alertMessage, "Face ID failed")
        XCTAssertTrue(store.isAuthenticationRequired)
        XCTAssertFalse(store.isAuthenticating)
    }

    @MainActor
    func testUnlockIfNeededSuppressesAlertForUserCancel() async throws {
        let storageRoot = makeTempDirectory()
        let libraryStore = RepositoryLibraryStore(rootURL: storageRoot)
        let localStore = libraryStore.repositoryStore(for: RepositoryReference.localRepositoryID)
        let now = fixtureDate("2026-04-16T09:00:00Z")
        try localStore.saveDescriptor(.local)
        try localStore.saveSnapshot(RepositorySnapshot(entries: [], updatedAt: now))
        try libraryStore.savePreferences(
            AppPreferences(
                defaultRepositoryID: RepositoryReference.localRepositoryID,
                isBiometricLockEnabled: true,
                isSharedUpdateNotificationEnabled: false
            )
        )

        let biometricAuthenticator = MockBiometricAuthenticator()
        biometricAuthenticator.results = [
            .success(()),
            .failure(LAError(.userCancel))
        ]
        let store = AppStore(
            libraryStore: libraryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now },
            authenticateBiometrics: biometricAuthenticator.authenticate
        )

        await store.loadIfNeeded()
        await store.handleScenePhaseChange(.background)
        await store.handleScenePhaseChange(.active)

        XCTAssertNil(store.alertMessage)
        XCTAssertTrue(store.isAuthenticationRequired)
        XCTAssertFalse(store.isAuthenticating)
    }
}

private struct StubLocalizedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
