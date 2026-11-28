import XCTest

/// The first-run setup guide (E8-S10) against the fakes: a fresh install that has not been asked for the
/// microphone. The look of the animations, Reduce Motion, and VoiceOver are in the device checklist (MA-80).
@MainActor
final class SetupGuideUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ scenario: [String] = []) {
        app.launchArguments =
            ["-LemmeTypeUITesting", "-LemmeTypeSetupGuide", "-LemmeTypeMicrophone", "notRequested"] + scenario
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private var primary: XCUIElement { app.buttons["setup.primary"] }

    func testAFreshInstallWalksTheGuideToDictate() {
        launch()
        XCTAssertTrue(element("setup.welcome").waitForExistence(timeout: 10))
        primary.tap()

        XCTAssertTrue(element("setup.microphone").waitForExistence(timeout: 5))
        XCTAssertEqual(primary.label, "Continue")
        XCTAssertFalse(app.buttons["setup.close"].exists, "no way out before the system prompt (5.1.1)")
        primary.tap()
        XCTAssertTrue(element("setup.microphone.allowed").waitForExistence(timeout: 5))
        primary.tap()

        XCTAssertTrue(element("setup.listening").waitForExistence(timeout: 5))
        app.buttons["setup.listening.later"].tap()

        XCTAssertTrue(element("setup.anyApp").waitForExistence(timeout: 5))
        XCTAssertTrue(element("settings.shortcut-guide").exists)
        primary.tap()

        XCTAssertTrue(element("setup.done").waitForExistence(timeout: 5))
        primary.tap()
        XCTAssertTrue(app.buttons["quick.record"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("setup.guide").exists)
    }

    func testADeniedMicrophoneStillLetsTheGuideGoOn() {
        launch(["-LemmeTypeMicrophoneAnswer", "denied"])
        XCTAssertTrue(element("setup.welcome").waitForExistence(timeout: 10))
        primary.tap()
        primary.tap()
        XCTAssertTrue(element("setup.microphone.denied").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setup.close"].isHittable)
        app.buttons["setup.close"].tap()
        XCTAssertTrue(app.buttons["quick.record"].waitForExistence(timeout: 5))
    }

    func testChoosingTheModelShowsTheDownloadConfirmation() {
        launch()
        XCTAssertTrue(element("setup.welcome").waitForExistence(timeout: 10))
        primary.tap()
        primary.tap()
        XCTAssertTrue(element("setup.microphone.allowed").waitForExistence(timeout: 5))
        primary.tap()
        XCTAssertTrue(element("setup.listening").waitForExistence(timeout: 5))
        app.buttons["setup.listening.onDevice"].tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.buttons["Download"].exists)
        confirmation.buttons["Cancel"].tap()
    }

    func testSettingsCanShowTheGuideAgain() {
        app.launchArguments = ["-LemmeTypeUITesting"]
        app.launch()
        XCTAssertTrue(app.buttons["quick.record"].waitForExistence(timeout: 10))
        XCTAssertFalse(element("setup.guide").exists, "an install that already used the app starts on Dictate")
        app.buttons["Settings"].tap()
        let show = app.buttons["settings.setupGuide"]
        for _ in 0..<12 where !show.isHittable { app.swipeUp() }
        show.tap()
        XCTAssertTrue(element("setup.welcome").waitForExistence(timeout: 5))
        app.buttons["setup.close"].tap()
        XCTAssertTrue(app.buttons["quick.record"].waitForExistence(timeout: 5))
    }
}
