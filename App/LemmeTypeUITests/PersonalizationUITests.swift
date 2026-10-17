import XCTest

/// Settings › Dictation › Replacements (E4-S4) against the in-memory store.
final class PersonalizationUITests: XCTestCase {
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
    func testAddsAndDeletesAReplacement() {
        let window = app.windows["settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let tab = window.tabs["Dictation"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()

        window.radioButtons["Replacements"].click()
        let add = window.buttons["personalization.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.click()

        // An empty entry is refused with a reason.
        let save = app.buttons["personalization.editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        XCTAssertTrue(app.staticTexts["personalization.editor.error"].waitForExistence(timeout: 5))

        let spoken = app.textFields["personalization.editor.primary"]
        spoken.click()
        spoken.typeText("my email")
        let written = app.textFields["personalization.editor.secondary"]
        written.click()
        written.typeText("pat@example.com")
        save.click()

        XCTAssertTrue(window.staticTexts["my email"].waitForExistence(timeout: 5))
        window.buttons["Delete my email"].click()
        XCTAssertFalse(window.staticTexts["my email"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testModesListBuiltInsAndDuplicateOne() {
        let window = app.windows["settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let tab = window.tabs["Dictation"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        window.radioButtons["Modes"].click()

        XCTAssertTrue(window.popUpButtons["modes.default"].waitForExistence(timeout: 5))
        let duplicate = window.buttons["Duplicate Message"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        XCTAssertFalse(window.buttons["Delete Message"].exists)  // built-ins can't be deleted
        duplicate.click()
        XCTAssertTrue(window.buttons["Delete Message Copy"].waitForExistence(timeout: 5))
    }
}
