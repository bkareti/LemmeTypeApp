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

    /// The Cloud speech switch in Settings (E13-S8): off until the person turns it on.
    func testCaptureTheCloudSpeechSwitch() {
        let settingsTab =
            app.tabBars.buttons["Settings"].exists
            ? app.tabBars.buttons["Settings"] : app.buttons.matching(identifier: "Settings").firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()
        let turnOn = app.descendants(matching: .any)["settings.cloud.turnOn"].firstMatch
        for _ in 0..<6 where !turnOn.exists { app.swipeUp() }
        XCTAssertTrue(turnOn.waitForExistence(timeout: 5))
        capture("07-cloud-speech")
    }

    /// The subscription offer, with the price StoreKit's test file also uses (E13-S8, Guideline 3.1.2).
    func testCaptureThePaywall() {
        app.terminate()
        app.launchArguments = ["-LemmeTypeUITesting", "-LemmeTypeNotSubscribed"]
        app.launch()
        let record = app.buttons["quick.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(app.buttons["paywall.start"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["paywall.price"].label.contains("$1.99"), true, "the price is StoreKit's")
        capture("08-paywall")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
