import XCTest

/// Settings › Dictation (E2-S9) against fake engines: Apple Speech is ready,
/// the Whisper model is not installed. Nothing is downloaded.
final class DictationSettingsUITests: XCTestCase {
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
    func testShowsModesEnginesAndBlockedStates() {
        openDictationPane()

        // Radio labels include the plain-language description after the title.
        XCTAssertTrue(radio(startingWith: "Exact Dictation").waitForExistence(timeout: 5))
        XCTAssertTrue(radio(startingWith: "Clean Writing").exists)
        XCTAssertTrue(radio(startingWith: "Automatic").exists)

        let whisper = window.radioButtons.matching(NSPredicate(format: "label CONTAINS 'Whisper'")).firstMatch
        XCTAssertTrue(whisper.waitForExistence(timeout: 5))
        whisper.click()
        let blocked = window.descendants(matching: .any)["dictation.engine.blocked"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDownloadAsksForConfirmationFirst() {
        openDictationPane()
        window.popUpButtons["dictation.section"].click()
        app.menuItems["Models"].click()
        let download = window.buttons["models.whisper-base-en.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        for _ in 0..<5 where !download.isHittable {
            window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200)
        }
        download.click()

        // Only the confirmation names where the file comes from.
        let message = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Hugging Face' OR label CONTAINS 'Hugging Face'")
        ).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label == 'Cancel'")).firstMatch.click()
        XCTAssertTrue(download.waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    @MainActor private var window: XCUIElement { app.windows["settings"] }

    @MainActor
    private func openDictationPane() {
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let tab = window.tabs["Dictation"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 1"), object: tab)
        if XCTWaiter().wait(for: [selected], timeout: 3) != .completed {
            tab.click()
        }
    }

    @MainActor
    private func radio(startingWith title: String) -> XCUIElement {
        window.radioButtons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
}
