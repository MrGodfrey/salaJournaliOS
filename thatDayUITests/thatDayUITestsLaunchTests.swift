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
        let storageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("thatDay-launch-\(UUID().uuidString)", isDirectory: true)
        app.launchEnvironment["THATDAY_STORAGE_ROOT"] = storageRoot.path
        app.launchEnvironment["THATDAY_RESET_STORAGE"] = "1"
        app.launchEnvironment["THATDAY_REFERENCE_DATE"] = "2026-04-16T09:00:00Z"
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
