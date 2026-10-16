import XCTest

/// Diagnostics export (E1-S7): preview shows the report before anything is saved.
final class DiagnosticsUITests: XCTestCase {
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
    func testPreviewShowsReportBeforeSaving() {
        let window = app.windows["settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let tab = window.tabs["Diagnostics"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()

        let preview = window.buttons["diagnostics.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.click()

        let content = window.sheets.firstMatch.staticTexts["diagnostics.content"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        let text = (content.value as? String) ?? content.label
        XCTAssertTrue(text.contains("\"appVersion\""))
        XCTAssertTrue(text.contains("\"hardwareModel\""))
        XCTAssertTrue(text.contains("\"permissions\""))
        XCTAssertTrue(text.contains("app.launched"))
        XCTAssertTrue(window.sheets.firstMatch.buttons["diagnostics.save"].exists)

        window.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertTrue(content.waitForNonExistence(timeout: 5))
    }
}
