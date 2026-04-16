import XCTest

final class thatDayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCalendarDateSelectionReturnsToJournal() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["openCalendarButton"].waitForExistence(timeout: 5))
        app.buttons["openCalendarButton"].tap()

        let targetDay = app.buttons["calendarDay-2026-04-17"]
        XCTAssertTrue(targetDay.waitForExistence(timeout: 5))
        targetDay.tap()

        let header = app.staticTexts["journalHeaderDate"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.label, "April 17")
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
        titleField.typeText("UI Test Blog Story")

        let bodyEditor = app.otherElements["entryBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText("This blog post is written during UI testing.")

        app.buttons["saveEntryButton"].tap()
        XCTAssertTrue(app.staticTexts["UI Test Blog Story"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Search"].tap()

        let searchField = app.textFields["searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("UI Test Blog Story")

        XCTAssertTrue(app.staticTexts["UI Test Blog Story"].waitForExistence(timeout: 5))
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
