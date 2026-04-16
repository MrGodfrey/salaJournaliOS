import CloudKit
import UIKit
import XCTest
@testable import thatDay

final class thatDayTests: XCTestCase {
    @MainActor
    func testJournalSectionsGroupEntriesByMonthDayAcrossYears() async throws {
        let entries = [
            makeEntry(title: "2026", happenedAt: fixtureDate("2026-04-16T09:00:00Z")),
            makeEntry(title: "2025", happenedAt: fixtureDate("2025-04-16T08:00:00Z")),
            makeEntry(title: "2024", happenedAt: fixtureDate("2024-04-16T07:00:00Z")),
            makeEntry(title: "2023", happenedAt: fixtureDate("2023-04-16T06:00:00Z")),
            makeEntry(title: "Ignore me", happenedAt: fixtureDate("2026-04-18T06:00:00Z"))
        ]
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: entries
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.journalSections.map(\.year), [2026, 2025, 2024, 2023])
        XCTAssertEqual(store.journalSections.first?.entries.first?.title, "2026")
    }

    @MainActor
    func testEmptySearchDoesNotShowAnyResults() async throws {
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [makeEntry(title: "Welcome", happenedAt: fixtureDate("2026-04-16T09:00:00Z"))]
        )

        await store.loadIfNeeded()

        XCTAssertTrue(store.searchResults.isEmpty)
    }

    @MainActor
    func testSearchMatchesJournalAndBlogContent() async throws {
        let entries = [
            makeEntry(title: "Morning Journal", happenedAt: fixtureDate("2026-04-16T09:00:00Z")),
            makeEntry(
                kind: .blog,
                title: "The Art of Morning Stillness",
                body: "A quiet morning changes the whole day.",
                happenedAt: fixtureDate("2026-04-15T09:00:00Z")
            )
        ]
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: entries
        )

        await store.loadIfNeeded()
        store.searchText = "morning"

        let titles = store.searchResults.map(\.title)
        XCTAssertTrue(titles.contains("Morning Journal"))
        XCTAssertTrue(titles.contains("The Art of Morning Stillness"))
    }

    @MainActor
    func testMovingSelectedDateAndReturningToToday() async throws {
        let store = try makeStore(now: fixtureDate("2026-04-16T09:00:00Z"))
        await store.loadIfNeeded()

        store.moveSelectedDate(by: 1)
        XCTAssertEqual(Calendar.current.dayIdentifier(for: store.selectedDate), "2026-04-17")

        store.returnToToday()
        XCTAssertEqual(Calendar.current.dayIdentifier(for: store.selectedDate), "2026-04-16")
    }

    @MainActor
    func testSettingDisplayedMonthUpdatesMonthAndYear() async throws {
        let store = try makeStore(now: fixtureDate("2026-04-16T09:00:00Z"))
        await store.loadIfNeeded()

        store.setDisplayedMonth(year: 2024, month: 2)

        XCTAssertEqual(Calendar.current.component(.year, from: store.displayedMonth), 2024)
        XCTAssertEqual(Calendar.current.component(.month, from: store.displayedMonth), 2)
        XCTAssertEqual(Calendar.current.component(.day, from: store.displayedMonth), 1)
    }

    func testCalendarGridBuildsCompleteWeeksAndSelection() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let displayedMonth = fixtureDate("2026-04-01T00:00:00Z")
        let selectedDate = fixtureDate("2026-04-17T00:00:00Z")
        let days = CalendarGridBuilder.makeMonthGrid(
            displayedMonth: displayedMonth,
            selectedDate: selectedDate,
            journalDates: [selectedDate],
            calendar: calendar
        )

        XCTAssertEqual(days.count, 35)
        XCTAssertEqual(days.first?.key, "2026-03-29")
        XCTAssertEqual(days.last?.key, "2026-05-02")
        XCTAssertEqual(days.first(where: \.isSelected)?.key, "2026-04-17")
        XCTAssertEqual(days.first(where: { $0.key == "2026-04-17" })?.hasJournalEntries, true)
    }

    @MainActor
    func testSavingBlogEntryPersistsToLocalStore() async throws {
        let storageRoot = makeTempDirectory()
        let repositoryStore = LocalRepositoryStore(rootURL: storageRoot)
        let cloudService = MockCloudRepositoryService()
        let store = AppStore(
            repositoryStore: repositoryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )

        await store.loadIfNeeded()
        store.showEditor(for: .blog)
        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .blog,
                title: "A New Persisted Blog",
                body: "Saved from unit tests.",
                happenedAt: fixtureDate("2026-04-16T09:00:00Z")
            ),
            importedImageData: nil
        )

        XCTAssertTrue(didSave)

        let reloadedStore = AppStore(
            repositoryStore: repositoryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await reloadedStore.loadIfNeeded()

        XCTAssertTrue(reloadedStore.blogEntries.contains(where: { $0.title == "A New Persisted Blog" }))
    }

    @MainActor
    func testAcceptingShareLinkReplacesEntriesAndLocksViewerRepository() async throws {
        let storageRoot = makeTempDirectory()
        let repositoryStore = LocalRepositoryStore(rootURL: storageRoot)
        let cloudService = MockCloudRepositoryService()
        cloudService.acceptedSharedRepository = AcceptedSharedRepository(
            descriptor: RepositoryDescriptor(
                zoneName: "shared-zone",
                zoneOwnerName: "_owner_",
                shareRecordName: "shared-record",
                role: .viewer
            ),
            snapshot: RepositorySnapshot(
                entries: [
                    EntryRecord(
                        kind: .journal,
                        title: "Shared Journal",
                        body: "Read only entry.",
                        happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                    )
                ],
                updatedAt: fixtureDate("2026-04-16T09:00:00Z")
            )
        )

        let store = AppStore(
            repositoryStore: repositoryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await store.loadIfNeeded()

        store.incomingShareLink = "https://www.icloud.com/share/mock-share"
        await store.acceptIncomingShareLink()

        XCTAssertEqual(store.repositoryDescriptor.role, .viewer)
        XCTAssertFalse(store.canEditRepository)
        XCTAssertEqual(store.entries.first?.title, "Shared Journal")

        let reloadedStore = AppStore(
            repositoryStore: repositoryStore,
            cloudService: cloudService,
            now: { self.fixtureDate("2026-04-16T09:00:00Z") }
        )
        await reloadedStore.loadIfNeeded()

        XCTAssertEqual(reloadedStore.repositoryDescriptor.role, .viewer)
    }

    @MainActor
    private func makeStore(now: Date, entries: [EntryRecord]? = nil) throws -> AppStore {
        let repositoryStore = LocalRepositoryStore(rootURL: makeTempDirectory())
        if let entries {
            try repositoryStore.saveSnapshot(RepositorySnapshot(entries: entries, updatedAt: now))
        }

        return AppStore(
            repositoryStore: repositoryStore,
            cloudService: MockCloudRepositoryService(),
            now: { now }
        )
    }

    private func makeEntry(
        kind: EntryKind = .journal,
        title: String,
        body: String = "Body",
        happenedAt: Date
    ) -> EntryRecord {
        EntryRecord(
            kind: kind,
            title: title,
            body: body,
            happenedAt: happenedAt,
            createdAt: happenedAt,
            updatedAt: happenedAt
        )
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixtureDate(_ rawValue: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue) ?? .now
    }
}

private final class MockCloudRepositoryService: CloudRepositoryServicing {
    var loadedSnapshot: RepositorySnapshot?
    var acceptedSharedRepository: AcceptedSharedRepository?

    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot {
        if let loadedSnapshot {
            return loadedSnapshot
        }

        throw CloudRepositoryError.repositoryNotFound
    }

    func saveSnapshot(_ snapshot: RepositorySnapshot, using descriptor: RepositoryDescriptor) async throws -> RepositoryDescriptor {
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

    func shareURL(using descriptor: RepositoryDescriptor, snapshot: RepositorySnapshot) async throws -> URL {
        URL(string: "https://www.icloud.com/share/mock-share")!
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
        if let acceptedSharedRepository {
            return acceptedSharedRepository
        }

        throw CloudRepositoryError.shareLinkInvalid
    }

    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository {
        try await acceptShare(from: URL(string: "https://www.icloud.com/share/mock-share")!)
    }
}
