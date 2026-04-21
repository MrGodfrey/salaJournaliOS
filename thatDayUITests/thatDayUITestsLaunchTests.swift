import XCTest

final class thatDayUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["THATDAY_STORAGE_ROOT"] = "thatDay-launch-\(UUID().uuidString)"
        app.launchEnvironment["THATDAY_RESET_STORAGE"] = "1"
        app.launchEnvironment["THATDAY_REFERENCE_DATE"] = "2026-04-16T09:00:00Z"
        app.launchEnvironment["THATDAY_UI_TEST_MODE"] = "1"
        app.launchEnvironment["THATDAY_APP_LANGUAGE"] = "en"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
