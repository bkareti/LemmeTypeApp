import XCTest

/// Settings › Privacy (E6-S4, E6-S5) against in-memory stores: history is off
/// on a fresh launch, the overview explains data use, and Delete All Local Data
/// asks first.
final class PrivacyUITests: XCTestCase {
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
    private func openPrivacy() -> XCUIElement {
        let window = app.windows["settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let tab = window.tabs["Privacy"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        return window
    }

    @MainActor
    func testOverviewExplainsPermissionsAndWhatIsKept() {
        let window = openPrivacy()
        XCTAssertTrue(window.staticTexts["privacy.intro"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["privacy.network"].exists)
        XCTAssertTrue(window.staticTexts["privacy.analytics"].exists)
        XCTAssertTrue(window.buttons["privacy.deleteAllData"].exists)
        XCTAssertTrue(window.checkBoxes["privacy.removeModels"].exists)
        XCTAssertEqual(window.checkBoxes["privacy.removeModels"].value as? Int, 0, "models stay by default")
    }

    @MainActor
    func testHistoryIsOffByDefault() {
        let window = openPrivacy()
        window.popUpButtons["privacy.section"].click()
        app.menuItems["History"].click()

        let toggle = window.checkBoxes["history.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 0, "History is off on a fresh launch")
        XCTAssertTrue(window.staticTexts["history.empty"].exists)
        XCTAssertFalse(window.buttons["history.deleteAll"].isEnabled)
        XCTAssertFalse(window.buttons["history.export"].isEnabled)

        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 1)
        XCTAssertTrue(window.popUpButtons["history.retention"].isEnabled)
    }

    @MainActor
    func testDeleteAllLocalDataAsksFirst() {
        let window = openPrivacy()
        let button = window.buttons["privacy.deleteAllData"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()

        let cancel = window.sheets.firstMatch.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(window.sheets.firstMatch.buttons["Delete All Local Data"].exists)
        cancel.click()
        XCTAssertFalse(window.staticTexts["privacy.erasureResult"].exists, "nothing was deleted")
    }
}
