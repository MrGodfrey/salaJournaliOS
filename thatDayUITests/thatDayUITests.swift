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
        XCTAssertFalse(app.staticTexts["欢迎使用 thatDay"].exists)
    }

    @MainActor
    func testCalendarMonthPickerAndNowReturnToToday() throws {
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
        XCTAssertEqual(monthButton.label, "May")

        let nowButton = app.buttons["calendarNowButton"]
        XCTAssertTrue(nowButton.waitForExistence(timeout: 5))
        nowButton.tap()
        XCTAssertEqual(monthButton.label, "April")
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

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let updatedListTitle = app.staticTexts["UI Test Blog Story Edited"]
        XCTAssertTrue(updatedListTitle.waitForExistence(timeout: 5))
        updatedListTitle.swipeLeft()

        let deleteButton = app.buttons["删除"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        let deleteConfirmation = app.alerts.buttons["删除"]
        XCTAssertTrue(deleteConfirmation.waitForExistence(timeout: 5))
        deleteConfirmation.tap()

        XCTAssertFalse(updatedListTitle.waitForExistence(timeout: 2))
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
    func testSettingsSheetOpensFromJournal() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["openSettingsButton"].waitForExistence(timeout: 5))
        app.buttons["openSettingsButton"].tap()

        XCTAssertTrue(app.buttons["acceptShareLinkButton"].waitForExistence(timeout: 5))
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        let storageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("thatDay-ui-\(UUID().uuidString)", isDirectory: true)

        app.launchEnvironment["THATDAY_STORAGE_ROOT"] = storageRoot.path
        app.launchEnvironment["THATDAY_RESET_STORAGE"] = "1"
        app.launchEnvironment["THATDAY_REFERENCE_DATE"] = "2026-04-16T09:00:00Z"
        app.launch()
        return app
    }
}
