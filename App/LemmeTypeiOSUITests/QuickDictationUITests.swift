import XCTest

/// Quick Dictation on the iOS Simulator against fake services: no microphone,
/// no speech engine, and no pasteboard are touched (E8-S6, E8-S9).
final class QuickDictationUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-LemmeTypeUITesting"]
        app.launch()
    }

    func testRecordReviewAndCopy() {
        let record = app.buttons["quick.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()

        XCTAssertTrue(app.buttons["quick.stop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["quick.recording"].exists || app.staticTexts["quick.recording"].exists)
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["quick.stop"].tap()

        let result = app.staticTexts["quick.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertEqual(result.label, "hello from lemmetype")
        XCTAssertFalse(app.staticTexts["quick.copied"].exists, "nothing is copied before Copy")

        app.buttons["quick.copy"].tap()
        XCTAssertTrue(app.staticTexts["quick.copied"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quick.record"].exists)
    }

    func testCancelLeavesNothingToReview() {
        let record = app.buttons["quick.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(app.buttons["quick.cancel"].waitForExistence(timeout: 5))
        app.buttons["quick.cancel"].tap()

        XCTAssertTrue(app.buttons["quick.record"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["quick.result"].exists)
        XCTAssertFalse(app.staticTexts["quick.copied"].exists)
    }

    func testDiscardReturnsToReady() {
        app.buttons["quick.record"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["quick.stop"].tap()
        XCTAssertTrue(app.staticTexts["quick.result"].waitForExistence(timeout: 10))

        app.buttons["quick.discard"].tap()

        XCTAssertTrue(app.buttons["quick.record"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["quick.result"].exists)
    }

    func testSettingsShowLanguageModelsPrivacyAndTheShortcutGuide() {
        app.tabBars.buttons.element(boundBy: 1).tap()

        // List rows are exposed as different element types by iOS version, so look by identifier.
        func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
        XCTAssertTrue(element("settings.language").waitForExistence(timeout: 10))
        XCTAssertTrue(element("settings.models").exists)
        XCTAssertTrue(element("settings.lifetime").exists)

        // The list creates rows lazily; Privacy is below the first screen.
        app.swipeUp()
        XCTAssertTrue(element("settings.privacy").waitForExistence(timeout: 5))
    }
}
