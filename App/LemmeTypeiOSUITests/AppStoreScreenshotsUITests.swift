import XCTest

/// App Store screenshots of the real screens, against the UI-test fakes (no microphone,
/// no engine). Runs only with LEMMETYPE_SCREENSHOTS=1; `scripts/make-app-store-screenshots.sh`
/// sets it, fixes the status bar, and collects the images.
@MainActor
final class AppStoreScreenshotsUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LEMMETYPE_SCREENSHOTS"] == "1", "screenshots are made on request")
        continueAfterFailure = false
        app.launchArguments = ["-LemmeTypeUITesting"]
        app.launchEnvironment["LEMMETYPE_RECOGNIZED_TEXT"] =
            "Running ten minutes late. Start without me, and I’ll catch up on the notes after the call."
        app.launch()
    }

    func testCaptureTheMainScreens() {
        let record = app.buttons["quick.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        capture("01-ready")

        record.tap()
        XCTAssertTrue(app.buttons["quick.stop"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.2)
        capture("02-recording")
        app.buttons["quick.stop"].tap()

        XCTAssertTrue(app.staticTexts["quick.result"].waitForExistence(timeout: 10))
        capture("03-review")

        app.buttons["quick.copy"].tap()
        XCTAssertTrue(app.staticTexts["quick.copied"].waitForExistence(timeout: 5))
        capture("04-copied")

        // iPhone has the tab bar at the bottom; iPad shows the tabs at the top. Both name it.
        let settingsTab =
            app.tabBars.buttons["Settings"].exists
            ? app.tabBars.buttons["Settings"] : app.buttons.matching(identifier: "Settings").firstMatch
        settingsTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.language"].firstMatch.waitForExistence(timeout: 10))
        capture("05-settings")

        // The list creates rows lazily; Privacy is below the first screen.
        app.swipeUp()
        let privacy = app.descendants(matching: .any)["settings.privacy"].firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        Thread.sleep(forTimeInterval: 0.8)
        capture("06-privacy")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
