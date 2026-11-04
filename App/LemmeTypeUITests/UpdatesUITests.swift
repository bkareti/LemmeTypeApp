import XCTest

/// Settings › General › Updates (E7-S3) against a fake release feed.
final class UpdatesUITests: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-LemmeTypeUITesting", "-LemmeTypeShowSettings"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    @MainActor
    func testCheckingShowsTheResultAndTheWeeklyCheckIsOffByDefault() {
        let window = app.windows["settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        // A Toggle is a switch on macOS 27 and a checkbox before it; match any type.
        let weekly = window.descendants(matching: .any)["updates.weekly"]
        XCTAssertTrue(weekly.waitForExistence(timeout: 5))
        XCTAssertEqual(weekly.value as? Int, 0, "no background checks unless the user turns them on")
        // macOS exposes a Text's words as its value, not its label.
        XCTAssertEqual(window.staticTexts["updates.status"].value as? String, "Not checked yet.")

        window.buttons["updates.check"].click()

        let status = window.staticTexts["updates.status"]
        let available = NSPredicate(format: "value CONTAINS 'is available'")
        expectation(for: available, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(window.buttons["updates.openPage"].exists)
    }
}
