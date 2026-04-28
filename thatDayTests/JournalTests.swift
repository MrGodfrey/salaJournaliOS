import XCTest
@testable import thatDay

final class JournalTests: AppStoreTestCase {
    @MainActor
    func testJournalEntriesFilterByMonthDayAcrossYearsAndStaySorted() async throws {
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

        XCTAssertEqual(store.journalEntries.map(\.title), ["2026", "2025", "2024", "2023"])
    }

    @MainActor
    func testJournalCardDateIncludesWeekdayBeforeYear() {
        let entry = makeEntry(
            title: "Weekday Journal",
            happenedAt: fixtureDate("2026-04-16T09:00:00Z")
        )

        XCTAssertEqual(entry.journalCardDateTitle, "Thursday, 2026")
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
    func testFreshInstallStartsWithEmptyLocalRepository() async throws {
        let storageRoot = makeTempDirectory()
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            rootURL: storageRoot
        )

        await store.loadIfNeeded()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.blogTags, RepositorySnapshot.defaultBlogTags)

        let localStore = RepositoryLibraryStore(rootURL: storageRoot)
            .repositoryStore(for: RepositoryReference.localRepositoryID)
        let snapshot = try XCTUnwrap(localStore.loadSnapshot())
        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertEqual(snapshot.blogTags, RepositorySnapshot.defaultBlogTags)
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
    func testSearchNormalizesCaseDiacriticsWhitespaceAndFindsMatchesAcrossTags() async throws {
        let entries = [
            makeEntry(
                kind: .blog,
                title: "Cafe Notes",
                body: "Reading over espresso.",
                blogTag: "Reading",
                happenedAt: fixtureDate("2026-04-16T09:00:00Z")
            ),
            makeEntry(
                kind: .blog,
                title: "Trip Recap",
                body: "A quiet CAFE morning by the sea.",
                blogTag: "Trip",
                happenedAt: fixtureDate("2026-04-15T09:00:00Z")
            ),
            makeEntry(
                title: "Ignored Journal",
                body: "Nothing related here.",
                happenedAt: fixtureDate("2026-04-14T09:00:00Z")
            )
        ]
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: entries
        )

        await store.loadIfNeeded()
        store.searchText = "  café  "

        XCTAssertEqual(Set(store.searchResults.map(\.title)), ["Cafe Notes", "Trip Recap"])
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
    func testJournalEntriesForExplicitPageDateDoNotMutateSelectedDate() async throws {
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [
                makeEntry(title: "Current Page", happenedAt: fixtureDate("2026-04-16T09:00:00Z")),
                makeEntry(title: "Next Page", happenedAt: fixtureDate("2026-04-17T09:00:00Z")),
                makeEntry(kind: .blog, title: "Ignored Blog", happenedAt: fixtureDate("2026-04-17T09:00:00Z"))
            ]
        )

        await store.loadIfNeeded()

        let nextPageEntries = store.journalEntries(for: fixtureDate("2026-04-17T09:00:00Z"))

        XCTAssertEqual(nextPageEntries.map(\.title), ["Next Page"])
        XCTAssertEqual(store.journalEntries.map(\.title), ["Current Page"])
        XCTAssertEqual(Calendar.current.dayIdentifier(for: store.selectedDate), "2026-04-16")
    }

    @MainActor
    func testJournalDateByAddingUsesCalendarDayBoundaries() async throws {
        let store = try makeStore(now: fixtureDate("2026-04-30T09:00:00Z"))
        await store.loadIfNeeded()

        let nextDay = store.journalDate(byAdding: 1, to: fixtureDate("2026-04-30T09:00:00Z"))
        let previousDay = store.journalDate(byAdding: -1, to: fixtureDate("2026-05-01T09:00:00Z"))

        XCTAssertEqual(Calendar.current.dayIdentifier(for: nextDay), "2026-05-01")
        XCTAssertEqual(Calendar.current.dayIdentifier(for: previousDay), "2026-04-30")
    }

    func testSearchBarTextSynchronizationPreservesMarkedTextComposition() {
        XCTAssertFalse(SearchBarTextSynchronization.shouldCommitUIKitChange(hasMarkedText: true))
        XCTAssertFalse(
            SearchBarTextSynchronization.shouldApplyBindingChange(
                currentText: "wangx",
                bindingText: "wang",
                hasMarkedText: true
            )
        )
        XCTAssertTrue(
            SearchBarTextSynchronization.shouldApplyBindingChange(
                currentText: "wang",
                bindingText: "王",
                hasMarkedText: false
            )
        )
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

    @MainActor
    func testPreviousMonthNextMonthAndGoToJournalUpdateCalendarState() async throws {
        let store = try makeStore(now: fixtureDate("2026-04-16T09:00:00Z"))
        await store.loadIfNeeded()

        store.previousMonth()
        XCTAssertEqual(Calendar.current.component(.year, from: store.displayedMonth), 2026)
        XCTAssertEqual(Calendar.current.component(.month, from: store.displayedMonth), 3)

        store.nextMonth()
        XCTAssertEqual(Calendar.current.component(.month, from: store.displayedMonth), 4)

        store.goToJournal(for: fixtureDate("2025-12-09T09:00:00Z"))

        XCTAssertEqual(store.selectedTab, .journal)
        XCTAssertEqual(Calendar.current.dayIdentifier(for: store.selectedDate), "2025-12-09")
        XCTAssertEqual(Calendar.current.component(.year, from: store.displayedMonth), 2025)
        XCTAssertEqual(Calendar.current.component(.month, from: store.displayedMonth), 12)
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
    func testSavingJournalEntryAllowsEmptyTitle() async throws {
        let store = try makeStore(now: fixtureDate("2026-04-16T09:00:00Z"))

        await store.loadIfNeeded()

        let didSave = await store.saveEntry(
            draft: EntryDraft(
                kind: .journal,
                title: "",
                body: "Saved without a title.",
                happenedAt: fixtureDate("2026-04-16T09:00:00Z")
            ),
            importedImageData: nil
        )

        XCTAssertTrue(didSave)
        XCTAssertEqual(store.journalEntries.first?.title, "")
        XCTAssertEqual(store.journalEntries.first?.body, "Saved without a title.")
    }

    @MainActor
    func testBlogEntriesDefaultToNoteTagAndWrittenStatisticsCountAllEntries() async throws {
        let entries = [
            makeEntry(
                title: "Morning Note",
                body: "Three calm lines",
                happenedAt: fixtureDate("2026-04-16T09:00:00Z")
            ),
            makeEntry(
                kind: .blog,
                title: "Reading Log",
                body: "Four quick test words",
                happenedAt: fixtureDate("2026-04-15T09:00:00Z")
            )
        ]
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: entries
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.blogEntries.first?.blogTag, "note")
        XCTAssertEqual(store.journalEntryCount, 1)
        XCTAssertEqual(store.blogEntryCount, 1)
        XCTAssertEqual(store.writtenWordCount, 11)
    }

    @MainActor
    func testWrittenWordCountAllowsZeroWords() async throws {
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [
                makeEntry(
                    title: "",
                    body: "",
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ]
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.writtenWordCount, 0)
        XCTAssertEqual(store.formattedWrittenWordCount, "0")
    }

    @MainActor
    func testWrittenWordCountStaysUnabbreviatedAt999Words() async throws {
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [
                makeEntry(
                    title: "One",
                    body: words(998),
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ]
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.writtenWordCount, 999)
        XCTAssertEqual(store.formattedWrittenWordCount, "999")
    }

    @MainActor
    func testWrittenWordCountUsesOneKAtExactlyOneThousandWords() async throws {
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [
                makeEntry(
                    title: "One",
                    body: words(999),
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ]
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.writtenWordCount, 1_000)
        XCTAssertEqual(store.formattedWrittenWordCount, "1.00K")
    }

    @MainActor
    func testWrittenWordCountUsesKAbbreviationAfterOneThousandWords() async throws {
        let largeBody = words(1_098)
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [
                makeEntry(
                    title: "Big Count",
                    body: largeBody,
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ]
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.writtenWordCount, 1_100)
        XCTAssertEqual(store.formattedWrittenWordCount, "1.10K")
    }

    @MainActor
    func testWrittenWordCountRoundsToThreeSignificantDigitsWithoutExtraDecimal() async throws {
        let largeBody = words(100_198)
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [
                makeEntry(
                    title: "Big Count",
                    body: largeBody,
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ]
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.writtenWordCount, 100_200)
        XCTAssertEqual(store.formattedWrittenWordCount, "100K")
    }

    @MainActor
    func testWrittenWordCountPromotesToNextAbbreviationWhenRoundedValueHitsOneThousand() async throws {
        let largeBody = words(999_498)
        let store = try makeStore(
            now: fixtureDate("2026-04-16T09:00:00Z"),
            entries: [
                makeEntry(
                    title: "Huge Count",
                    body: largeBody,
                    happenedAt: fixtureDate("2026-04-16T09:00:00Z")
                )
            ]
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.writtenWordCount, 999_500)
        XCTAssertEqual(store.formattedWrittenWordCount, "1.00M")
    }
}
