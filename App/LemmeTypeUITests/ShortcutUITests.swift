import XCTest

/// Global shortcut (E1-S4). Uses the real Carbon hot-key registration (no
/// permission needed) with a fake activation target.
final class ShortcutUITests: XCTestCase {
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
    func testDefaultShortcutIsShownAndRegistered() {
        openShortcutPane()
        XCTAssertEqual(text(of: current), "⌥Space")
        XCTAssertFalse(window.staticTexts["shortcut.error"].exists)
    }

    @MainActor
    func testPushToTalkPressAndReleaseStartsThenStops() {
        openShortcutPane()
        app.typeKey(" ", modifierFlags: .option)

        XCTAssertTrue(waitForActivity("Stopped"))
    }

    @MainActor
    func testToggleStartsOnFirstPressAndStopsOnSecond() {
        openShortcutPane()
        chooseToggleMode()

        app.typeKey(" ", modifierFlags: .option)
        XCTAssertTrue(waitForActivity("Started in TextEdit"))

        app.typeKey(" ", modifierFlags: .option)
        XCTAssertTrue(waitForActivity("Stopped"))
    }

    @MainActor
    func testEscapeCancelsAnActiveSession() {
        openShortcutPane()
        chooseToggleMode()
        app.typeKey(" ", modifierFlags: .option)
        XCTAssertTrue(waitForActivity("Started in TextEdit"))

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(waitForActivity("Cancelled"))
    }

    @MainActor
    func testRecordingANewShortcutReplacesTheOldOne() {
        openShortcutPane()
        window.buttons["shortcut.record"].click()
        XCTAssertTrue(waitForText("Type a shortcut…", in: current))
        app.typeKey("d", modifierFlags: [.control, .option])

        XCTAssertTrue(waitForText("⌃⌥D", in: current), "shows \(text(of: current))")
        chooseToggleMode()
        app.typeKey("d", modifierFlags: [.control, .option])
        XCTAssertTrue(waitForActivity("Started in TextEdit"))
    }

    @MainActor
    func testInvalidShortcutShowsRecoverableError() {
        openShortcutPane()
        window.buttons["shortcut.record"].click()
        XCTAssertTrue(waitForText("Type a shortcut…", in: current))
        app.typeKey("d", modifierFlags: [])

        XCTAssertTrue(window.staticTexts["shortcut.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForText("⌥Space", in: current))
        XCTAssertTrue(window.buttons["shortcut.record"].isEnabled)
    }

    // MARK: - Helpers

    @MainActor
    private func openShortcutPane() {
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        selectTab("Shortcut")
        XCTAssertTrue(current.waitForExistence(timeout: 5))
    }

    @MainActor private var window: XCUIElement { app.windows["settings"] }
    @MainActor private var current: XCUIElement { window.staticTexts["shortcut.current"] }

    @MainActor
    private func chooseToggleMode() {
        let toggle = window.radioButtons["Toggle — press to start and stop"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
    }

    @MainActor
    private func selectTab(_ title: String) {
        let tab = window.tabs[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 1"), object: tab)
        if XCTWaiter().wait(for: [expectation], timeout: 3) != .completed {
            tab.click()
        }
    }

    @MainActor
    private func waitForActivity(_ expected: String) -> Bool {
        waitForText(expected, in: window.staticTexts["shortcut.lastActivity"])
    }

    @MainActor
    private func waitForText(_ expected: String, in element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if element.exists && text(of: element) == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    @MainActor
    private func text(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }
}
