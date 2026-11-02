import XCTest

/// E7-S7: with every string doubled in length, and again in a right-to-left
/// layout, the audited panes still show their controls. Run with UI Automation
/// Mode on a Mac with a GUI session.
final class PseudoLocalizationUITests: XCTestCase {
    private let tabs = [
        "General", "Dictation", "Shortcut", "Context", "Audio", "Permissions", "Privacy", "Diagnostics",
    ]

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LemmeTypeUITesting", "-LemmeTypeShowSettings"] + extra
        app.launch()
        return app
    }

    @MainActor
    private func everyPaneShowsItsControls(_ app: XCUIApplication) {
        let window = app.windows["settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for name in tabs {
            let tab = window.tabs[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(name) tab exists")
            tab.click()
            let controls =
                window.buttons.count + window.checkBoxes.count + window.popUpButtons.count + window.staticTexts.count
            XCTAssertGreaterThan(controls, 0, "\(name) shows controls")
            for button in window.buttons.allElementsBoundByIndex where button.isHittable {
                XCTAssertGreaterThan(button.frame.width, 8, "\(name): a button is not squeezed to nothing")
            }
        }
    }

    @MainActor
    func testDoubleLengthStrings() {
        let app = launch(["-NSDoubleLocalizedStrings", "YES"])
        everyPaneShowsItsControls(app)
        app.terminate()
    }

    @MainActor
    func testRightToLeftLayout() {
        let app = launch(["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
        everyPaneShowsItsControls(app)
        app.terminate()
    }
}
