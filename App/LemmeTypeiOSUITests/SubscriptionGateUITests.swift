import XCTest

/// E13-S5: without a trial or subscription a dictation start shows the paywall and records nothing, and the
/// person can still reach everything that is theirs. Against fake services only: no App Store, no microphone.
@MainActor
final class SubscriptionGateUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-LemmeTypeUITesting", "-LemmeTypeNotSubscribed"]
        app.launch()
    }

    func testABlockedStartShowsThePaywallAndClosingReturnsToTheSameScreen() {
        let record = app.buttons["quick.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()

        XCTAssertTrue(app.buttons["paywall.start"].waitForExistence(timeout: 10), "the offer is shown")
        XCTAssertFalse(app.buttons["quick.stop"].exists, "nothing is recording")
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        XCTAssertTrue(app.links["paywall.terms"].exists || app.buttons["paywall.terms"].exists)
        XCTAssertTrue(app.links["paywall.privacy"].exists || app.buttons["paywall.privacy"].exists)

        app.buttons["paywall.close"].tap()
        // The refusal stays on the Dictate screen until it is dismissed; nothing was recorded.
        XCTAssertTrue(app.staticTexts["quick.attention"].waitForExistence(timeout: 5), "the screen says why")
        XCTAssertFalse(app.buttons["quick.stop"].exists)
        app.buttons["quick.action.discard"].tap()
        XCTAssertTrue(app.buttons["quick.record"].waitForExistence(timeout: 5), "back on the same screen")
    }

    func testBuyingFromThePaywallUnlocksDictationOnTheSameScreen() {
        app.buttons["quick.record"].tap()
        XCTAssertTrue(app.buttons["paywall.start"].waitForExistence(timeout: 10))
        app.buttons["paywall.start"].tap()
        XCTAssertTrue(app.buttons["quick.record"].waitForExistence(timeout: 10), "the paywall closed by itself")

        app.buttons["quick.record"].tap()
        XCTAssertTrue(app.buttons["quick.stop"].waitForExistence(timeout: 5), "and dictation now starts")
        app.buttons["quick.cancel"].tap()
    }

    func testSettingsAndTheSubscriptionStayOpenWithoutASubscription() {
        app.tabBars.buttons.element(boundBy: 1).tap()
        func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        XCTAssertTrue(element("settings.subscription.status").waitForExistence(timeout: 10))
        XCTAssertEqual(element("settings.subscription.status").label, "Not subscribed.")
        XCTAssertTrue(element("settings.subscription.start").exists)
        XCTAssertTrue(element("settings.subscription.manage").exists)
        XCTAssertTrue(element("settings.subscription.restore").exists)
        XCTAssertTrue(element("settings.language").exists, "settings are not locked")
    }
}
