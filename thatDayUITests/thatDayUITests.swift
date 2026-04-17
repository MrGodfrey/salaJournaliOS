import XCTest

final class thatDayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSearchRequiresQueryBeforeShowingResults() throws {
        let app = launchApp()

        app.tabBars.buttons["Search"].tap()

        XCTAssertTrue(app.textFields["searchField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Welcome to thatDay"].exists)
    }

    @MainActor
    func testCalendarMonthPickerAndTodayReturnToCurrentMonth() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["openCalendarButton"].waitForExistence(timeout: 5))
        app.buttons["openCalendarButton"].tap()

        let monthButton = app.buttons["calendarMonthPickerButton"]
        XCTAssertTrue(monthButton.waitForExistence(timeout: 5))
        monthButton.tap()

        let monthWheel = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(monthWheel.waitForExistence(timeout: 5))
        monthWheel.adjust(toPickerWheelValue: "May")

        app.buttons["calendarPickerDoneButton"].tap()
        XCTAssertTrue(monthButton.label.contains("May 2026"))

        let todayButton = app.buttons["calendarTodayButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        XCTAssertTrue(monthButton.label.contains("April 2026"))
    }

    @MainActor
    func testJournalHeaderDateReturnsToToday() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["openCalendarButton"].waitForExistence(timeout: 5))
        app.buttons["openCalendarButton"].tap()

        let targetDay = app.buttons["calendarDay-2026-04-17"]
        XCTAssertTrue(targetDay.waitForExistence(timeout: 5))
        targetDay.tap()

        let headerButton = app.buttons["journalHeaderDateButton"]
        XCTAssertTrue(headerButton.waitForExistence(timeout: 5))
        XCTAssertEqual(headerButton.label, "April 17")

        headerButton.tap()
        XCTAssertEqual(headerButton.label, "April 16")
    }

    @MainActor
    func testJournalPreviousAndNextButtonsSwitchDates() throws {
        let app = launchApp()

        let headerButton = app.buttons["journalHeaderDateButton"]
        XCTAssertTrue(headerButton.waitForExistence(timeout: 5))
        XCTAssertEqual(headerButton.label, "April 16")

        app.buttons["journalNextDayButton"].tap()
        XCTAssertEqual(headerButton.label, "April 17")

        app.buttons["journalPreviousDayButton"].tap()
        XCTAssertEqual(headerButton.label, "April 16")
    }

    @MainActor
    func testCreateEditAndDeleteBlogPost() throws {
        let app = launchApp()

        app.tabBars.buttons["Blog"].tap()
        XCTAssertTrue(app.buttons["addBlogEntryButton"].waitForExistence(timeout: 5))
        app.buttons["addBlogEntryButton"].tap()

        let titleField = app.textFields["entryTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("UI Test Blog Story")

        let bodyEditor = app.textViews.element(boundBy: 0)
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText("This blog post is written during UI testing.")

        app.buttons["saveEntryButton"].tap()

        let createdTitle = app.staticTexts["UI Test Blog Story"]
        XCTAssertTrue(createdTitle.waitForExistence(timeout: 5))
        createdTitle.tap()

        let editButton = app.buttons["entryDetailEditButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let detailTitleField = app.textFields["entryTitleField"]
        XCTAssertTrue(detailTitleField.waitForExistence(timeout: 5))
        detailTitleField.tap()
        detailTitleField.typeText(" Edited")

        app.buttons["entryDetailSaveButton"].tap()

        let updatedTitle = app.staticTexts["UI Test Blog Story Edited"]
        XCTAssertTrue(updatedTitle.waitForExistence(timeout: 5))

        editButton.tap()

        let deleteButton = app.buttons["entryDetailDeleteButton"]
        scrollToElement(deleteButton, in: app)
        XCTAssertTrue(deleteButton.exists)
        deleteButton.tap()

        let deleteConfirmation = app.alerts.buttons["Delete"]
        XCTAssertTrue(deleteConfirmation.waitForExistence(timeout: 5))
        deleteConfirmation.tap()

        XCTAssertFalse(app.staticTexts["UI Test Blog Story Edited"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCreateBlogPostAppearsInSearch() throws {
        let app = launchApp()

        app.tabBars.buttons["Blog"].tap()
        XCTAssertTrue(app.buttons["addBlogEntryButton"].waitForExistence(timeout: 5))
        app.buttons["addBlogEntryButton"].tap()

        let titleField = app.textFields["entryTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Searchable Blog Story")

        let bodyEditor = app.textViews.element(boundBy: 0)
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText("This blog post should appear in search results.")

        app.buttons["saveEntryButton"].tap()
        XCTAssertTrue(app.staticTexts["Searchable Blog Story"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Search"].tap()

        let searchField = app.textFields["searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Searchable Blog Story")

        XCTAssertTrue(app.staticTexts["Searchable Blog Story"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBlogTagFilterShowsOnlyMatchingPosts() throws {
        let app = launchApp { storageRoot in
            try self.seedTaggedBlogRepository(at: storageRoot)
        }

        app.tabBars.buttons["Blog"].tap()

        XCTAssertTrue(app.staticTexts["Reading Summary"].waitForExistence(timeout: 5))

        let tripFilter = app.buttons["blogTagFilter-Trip"]
        XCTAssertTrue(tripFilter.waitForExistence(timeout: 5))
        tripFilter.tap()

        XCTAssertTrue(app.staticTexts["Trip Recap"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Reading Summary"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testNoImageBlogDetailUsesLeadingInsetLayout() throws {
        let app = launchApp()

        app.tabBars.buttons["Blog"].tap()
        XCTAssertTrue(app.buttons["addBlogEntryButton"].waitForExistence(timeout: 5))
        app.buttons["addBlogEntryButton"].tap()

        let titleField = app.textFields["entryTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("No Image Layout Check")

        let bodyEditor = app.textViews.element(boundBy: 0)
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText("Body paragraph one.\n\nBody paragraph two.")

        app.buttons["saveEntryButton"].tap()

        let createdTitle = app.staticTexts["No Image Layout Check"]
        XCTAssertTrue(createdTitle.waitForExistence(timeout: 5))
        createdTitle.tap()

        let detailTitle = app.staticTexts["entryDetailTitle"]
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(detailTitle.frame.minX, 16)

        let detailBody = app.staticTexts["entryDetailBody"]
        XCTAssertTrue(detailBody.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(detailBody.frame.minX, 16)
        XCTAssertLessThan(detailTitle.frame.minX, app.windows.element(boundBy: 0).frame.width / 2)
        XCTAssertLessThanOrEqual(abs(detailTitle.frame.minX - detailBody.frame.minX), 12)
    }

    @MainActor
    func testSettingsSheetOpensFromJournal() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["openSettingsButton"].waitForExistence(timeout: 5))
        app.buttons["openSettingsButton"].tap()

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current Repository"].exists)
    }

    @MainActor
    func testReadOnlyRepositoryHidesCreateButtonsInJournalAndBlog() throws {
        let app = launchApp { storageRoot in
            try self.seedReadOnlyRepository(at: storageRoot)
        }

        XCTAssertTrue(app.buttons["openSettingsButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addJournalEntryButton"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Blog"].tap()
        XCTAssertFalse(app.buttons["addBlogEntryButton"].waitForExistence(timeout: 2))
    }

    private func launchApp(prepareStorage: ((URL) throws -> Void)? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let storageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("thatDay-ui-\(UUID().uuidString)", isDirectory: true)

        if let prepareStorage {
            do {
                try prepareStorage(storageRoot)
            } catch {
                XCTFail("Failed to prepare storage: \(error)")
            }
        }

        app.launchEnvironment["THATDAY_STORAGE_ROOT"] = storageRoot.path
        app.launchEnvironment["THATDAY_RESET_STORAGE"] = prepareStorage == nil ? "1" : "0"
        app.launchEnvironment["THATDAY_REFERENCE_DATE"] = "2026-04-16T09:00:00Z"
        app.launch()
        return app
    }

    private func seedReadOnlyRepository(at storageRoot: URL) throws {
        let fileManager = FileManager.default
        let repositoriesRoot = storageRoot.appendingPathComponent("repositories", isDirectory: true)
        let repositoryID = "read-only-repository"
        let repositoryRoot = repositoriesRoot.appendingPathComponent(repositoryID, isDirectory: true)
        let isoDate = "2026-04-16T09:00:00Z"

        try fileManager.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)

        let descriptor: [String: Any] = [
            "role": "viewer"
        ]
        let snapshot: [String: Any] = [
            "entries": [
                [
                    "id": "2B1F9BC2-9037-4B9F-8FE8-B85AE6FC0FA0",
                    "kind": "journal",
                    "title": "Read-Only Journal",
                    "body": "This repository should hide create actions.",
                    "happenedAt": isoDate,
                    "createdAt": isoDate,
                    "updatedAt": isoDate
                ],
                [
                    "id": "2B1F9BC2-9037-4B9F-8FE8-B85AE6FC0FA1",
                    "kind": "blog",
                    "title": "Read-Only Blog",
                    "body": "Blog creation should also be hidden.",
                    "happenedAt": isoDate,
                    "createdAt": isoDate,
                    "updatedAt": isoDate
                ]
            ],
            "updatedAt": isoDate,
            "embeddedImages": []
        ]
        let catalog: [[String: Any]] = [
            [
                "id": repositoryID,
                "displayName": "Read-Only Repository",
                "descriptor": descriptor,
                "source": "shared",
                "lastKnownSnapshotUpdatedAt": isoDate,
                "subscribedAt": isoDate
            ]
        ]
        let preferences: [String: Any] = [
            "defaultRepositoryID": repositoryID,
            "isBiometricLockEnabled": false,
            "isSharedUpdateNotificationEnabled": false
        ]

        try writeJSON(catalog, to: storageRoot.appendingPathComponent("repositories.json"))
        try writeJSON(preferences, to: storageRoot.appendingPathComponent("preferences.json"))
        try writeJSON(descriptor, to: repositoryRoot.appendingPathComponent("descriptor.json"))
        try writeJSON(snapshot, to: repositoryRoot.appendingPathComponent("repository.json"))
    }

    private func seedTaggedBlogRepository(at storageRoot: URL) throws {
        let fileManager = FileManager.default
        let repositoryRoot = storageRoot
            .appendingPathComponent("repositories", isDirectory: true)
            .appendingPathComponent("local", isDirectory: true)
        let isoDate = "2026-04-16T09:00:00Z"

        try fileManager.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)

        let descriptor: [String: Any] = [
            "role": "local"
        ]
        let snapshot: [String: Any] = [
            "blogTags": ["Reading", "Trip", "note"],
            "entries": [
                [
                    "id": "6B1F9BC2-9037-4B9F-8FE8-B85AE6FC0FA0",
                    "kind": "blog",
                    "title": "Reading Summary",
                    "body": "A reading note.",
                    "blogTag": "Reading",
                    "happenedAt": isoDate,
                    "createdAt": isoDate,
                    "updatedAt": isoDate
                ],
                [
                    "id": "6B1F9BC2-9037-4B9F-8FE8-B85AE6FC0FA1",
                    "kind": "blog",
                    "title": "Trip Recap",
                    "body": "A trip note.",
                    "blogTag": "Trip",
                    "happenedAt": isoDate,
                    "createdAt": isoDate,
                    "updatedAt": isoDate
                ]
            ],
            "updatedAt": isoDate
        ]

        try writeJSON(descriptor, to: repositoryRoot.appendingPathComponent("descriptor.json"))
        try writeJSON(snapshot, to: repositoryRoot.appendingPathComponent("repository.json"))
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }
}
