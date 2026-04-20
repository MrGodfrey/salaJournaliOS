import XCTest
import UIKit

final class thatDayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "App and System Alerts") { alert in
            self.dismissAlert(alert)
        }
    }

    @MainActor
    func testFreshInstallShowsEmptyJournalInsteadOfWelcomeEntry() throws {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["No journal entries on this day"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Welcome to thatDay"].exists)
    }

    @MainActor
    func testSearchRequiresQueryBeforeShowingResults() throws {
        let app = launchApp()

        app.tabBars.buttons["Search"].tap()

        XCTAssertTrue(searchField(in: app).waitForExistence(timeout: 5))
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
    func testCreateJournalEntryWithoutTitle() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["addJournalEntryButton"].waitForExistence(timeout: 5))
        app.buttons["addJournalEntryButton"].tap()

        let titleField = app.textFields["entryTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(titleField.placeholderValue, "Title (Optional)")

        let bodyEditor = app.textViews.element(boundBy: 0)
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText("Saved without a title.")

        app.buttons["saveEntryButton"].tap()

        XCTAssertTrue(app.staticTexts["Saved without a title."].waitForExistence(timeout: 5))
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
    func testBlogEditorPersistsImageLayoutSelection() throws {
        let app = launchApp()

        app.tabBars.buttons["Blog"].tap()
        XCTAssertTrue(app.buttons["addBlogEntryButton"].waitForExistence(timeout: 5))
        app.buttons["addBlogEntryButton"].tap()

        let titleField = app.textFields["entryTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Portrait Preference")

        let layoutPicker = app.segmentedControls["entryBlogImageLayoutPicker"]
        XCTAssertTrue(layoutPicker.waitForExistence(timeout: 5))
        layoutPicker.buttons["Portrait"].tap()

        let bodyEditor = app.textViews.element(boundBy: 0)
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText("This post should remember its portrait card preference.")

        app.buttons["saveEntryButton"].tap()

        let createdTitle = app.staticTexts["Portrait Preference"]
        XCTAssertTrue(createdTitle.waitForExistence(timeout: 5))
        createdTitle.tap()

        let editButton = app.buttons["entryDetailEditButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let persistedLayoutPicker = app.segmentedControls["entryBlogImageLayoutPicker"]
        XCTAssertTrue(persistedLayoutPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(persistedLayoutPicker.buttons["Portrait"].isSelected)
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

        let searchField = searchField(in: app)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Searchable Blog Story")

        XCTAssertTrue(app.staticTexts["Searchable Blog Story"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSearchClearButtonRemovesQueryAndHidesResults() throws {
        let app = launchApp(seed: .taggedBlog)

        app.tabBars.buttons["Search"].tap()

        let searchField = searchField(in: app)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Trip")

        XCTAssertTrue(app.staticTexts["Trip Recap"].waitForExistence(timeout: 5))

        let clearButton = clearButton(in: searchField)
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        clearButton.tap()

        XCTAssertTrue(app.staticTexts["Start typing to search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Trip Recap"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testBlogTagFilterShowsOnlyMatchingPosts() throws {
        let app = launchApp(seed: .taggedBlog)

        app.tabBars.buttons["Blog"].tap()

        XCTAssertTrue(app.staticTexts["Reading Summary"].waitForExistence(timeout: 5))

        let tripFilter = app.buttons["blogTagFilter-Trip"]
        XCTAssertTrue(tripFilter.waitForExistence(timeout: 5))
        tripFilter.tap()

        XCTAssertTrue(app.staticTexts["Trip Recap"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Reading Summary"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testPortraitBlogCardUsesSideBySideLayout() throws {
        let app = launchApp(seed: .portraitBlog)

        app.tabBars.buttons["Blog"].tap()

        let title = app.staticTexts["Interstellar (2014)"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        XCTAssertGreaterThan(title.frame.minX, 100)
    }

    @MainActor
    func testPortraitBlogDetailCapsCoverHeightWithoutCroppingWidth() throws {
        let app = launchApp(seed: .portraitBlog)

        app.tabBars.buttons["Blog"].tap()

        let title = app.staticTexts["Interstellar (2014)"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()

        let cover = app.otherElements["entryDetailCover-7BFC7E5E-EBB3-46D0-B2D0-A9CE4B63B8B2"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(cover.frame.width, app.windows.firstMatch.frame.width * 0.85)
        XCTAssertGreaterThan(cover.frame.height, cover.frame.width)
        XCTAssertLessThan(cover.frame.height, cover.frame.width * 1.4)
    }

    @MainActor
    func testCalendarTagStatisticOpensBlogWithMatchingFilter() throws {
        let app = launchApp(seed: .taggedBlog)

        app.tabBars.buttons["Calendar"].tap()

        let tripStatistic = app.buttons["calendarBlogTagStat-Trip"]
        if !tripStatistic.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        if !tripStatistic.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(tripStatistic.waitForExistence(timeout: 5))
        tripStatistic.tap()

        XCTAssertTrue(app.staticTexts["Trip Recap"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Reading Summary"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCalendarTagStatisticsUseContentWidth() throws {
        let app = launchApp(seed: .taggedBlog)

        app.tabBars.buttons["Calendar"].tap()

        let readingStatistic = app.buttons["calendarBlogTagStat-Reading"]
        let tripStatistic = app.buttons["calendarBlogTagStat-Trip"]

        if !readingStatistic.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        if !readingStatistic.waitForExistence(timeout: 1) {
            app.swipeUp()
        }

        XCTAssertTrue(readingStatistic.waitForExistence(timeout: 5))
        XCTAssertTrue(tripStatistic.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(readingStatistic.frame.width, tripStatistic.frame.width + 20)
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
        XCTAssertTrue(app.descendants(matching: .any)["currentRepositoryPicker"].exists)
        XCTAssertTrue(app.staticTexts["Blog Tags"].exists)
    }

    @MainActor
    func testSettingsBlogTagsReorderWithLongPressDrag() throws {
        let app = launchApp(seed: .taggedBlog)

        XCTAssertTrue(app.buttons["openSettingsButton"].waitForExistence(timeout: 5))
        app.buttons["openSettingsButton"].tap()

        let readingRow = app.descendants(matching: .any)["settingsBlogTagRow-Reading"]
        let tripRow = app.descendants(matching: .any)["settingsBlogTagRow-Trip"]
        XCTAssertTrue(readingRow.waitForExistence(timeout: 5))
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))

        tripRow.press(forDuration: 1.2, thenDragTo: readingRow)

        XCTAssertTrue(waitUntil(timeout: 5) {
            tripRow.frame.minY < readingRow.frame.minY
        })

        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["openSettingsButton"].waitForExistence(timeout: 5))
        app.buttons["openSettingsButton"].tap()

        let persistedReadingRow = app.descendants(matching: .any)["settingsBlogTagRow-Reading"]
        let persistedTripRow = app.descendants(matching: .any)["settingsBlogTagRow-Trip"]
        XCTAssertTrue(persistedReadingRow.waitForExistence(timeout: 5))
        XCTAssertTrue(persistedTripRow.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) {
            persistedTripRow.frame.minY < persistedReadingRow.frame.minY
        })
    }

    @MainActor
    func testReadOnlyRepositoryHidesCreateButtonsInJournalAndBlog() throws {
        let app = launchApp(seed: .readOnlyRepository)

        XCTAssertTrue(app.buttons["openSettingsButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addJournalEntryButton"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Blog"].tap()
        XCTAssertFalse(app.buttons["addBlogEntryButton"].waitForExistence(timeout: 2))
    }

    private func launchApp(seed: UITestSeedScenario? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["THATDAY_STORAGE_ROOT"] = "thatDay-ui-\(UUID().uuidString)"
        app.launchEnvironment["THATDAY_RESET_STORAGE"] = "1"
        app.launchEnvironment["THATDAY_REFERENCE_DATE"] = "2026-04-16T09:00:00Z"
        app.launchEnvironment["THATDAY_UI_TEST_MODE"] = "1"
        if let seed {
            app.launchEnvironment["THATDAY_UI_TEST_SEED"] = seed.rawValue
        }
        app.launch()
        app.tap()
        dismissBlockingAlertIfPresent(in: app)
        return app
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        dismissBlockingAlertIfPresent(in: app)
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < maxSwipes {
            app.swipeUp()
            dismissBlockingAlertIfPresent(in: app)
            attempts += 1
        }
    }

    private func dismissBlockingAlertIfPresent(in app: XCUIApplication) {
        if app.alerts.firstMatch.exists {
            _ = dismissAlert(app.alerts.firstMatch)
        }

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.exists {
            _ = dismissAlert(springboard.alerts.firstMatch)
        }
    }

    private func dismissAlert(_ alert: XCUIElement) -> Bool {
        let preferredButtons = [
            "OK",
            "Allow",
            "Don’t Allow",
            "Don't Allow",
            "Not Now",
            "Continue",
            "Close",
            "Later"
        ]

        for title in preferredButtons {
            let button = alert.buttons[title]
            if button.exists {
                button.tap()
                return true
            }
        }

        if alert.buttons.firstMatch.exists {
            alert.buttons.firstMatch.tap()
            return true
        }

        return false
    }

    private func searchField(in app: XCUIApplication) -> XCUIElement {
        let identifiedSearchField = app.searchFields["searchField"]
        if identifiedSearchField.exists {
            return identifiedSearchField
        }

        let identifiedTextField = app.textFields["searchField"]
        if identifiedTextField.exists {
            return identifiedTextField
        }

        return app.searchFields.firstMatch
    }

    private func clearButton(in searchField: XCUIElement) -> XCUIElement {
        let clearTextButton = searchField.buttons["Clear text"]
        if clearTextButton.exists {
            return clearTextButton
        }

        let clearButton = searchField.buttons["Clear"]
        if clearButton.exists {
            return clearButton
        }

        return searchField.buttons.firstMatch
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return condition()
    }
}

private enum UITestSeedScenario: String {
    case taggedBlog = "tagged-blog"
    case portraitBlog = "portrait-blog"
    case readOnlyRepository = "read-only-repository"
}
