import XCTest

/// Menu-bar lifecycle (E1-S2) smoke tests against fake services
/// (`-LemmeTypeUITesting`), so the host's permissions and login items are
/// never touched.
///
/// XCUITest re-activates the app before clicking any element, which dismisses
/// an open status-bar menu, so menu items are checked for presence and state
/// here; the item actions are covered by `AppControllerTests` and the
/// manual checklist (MA-3).
final class LaunchUITests: XCTestCase {
    // Created in setUp: XCUIApplication's initializer is main-actor isolated,
    // so it cannot be a stored-property default in a nonisolated XCTestCase.
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app.terminate()
    }

    @MainActor
    func testLaunchShowsMenuBarItemAndNoWindow() {
        launch()

        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        XCTAssertFalse(settingsWindow.exists)
    }

    @MainActor
    func testStatusMenuOffersLifecycleActions() {
        launch()
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        statusItem.click()

        for title in ["Finish Setup…", "Settings…", "About LemmeType", "Quit LemmeType"] {
            let item = statusItem.menuItems[title]
            XCTAssertTrue(item.waitForExistence(timeout: 5), "\(title) is missing")
            XCTAssertTrue(item.isEnabled, "\(title) is disabled")
        }
        // Enabled by E1-S6 once recording exists.
        XCTAssertFalse(statusItem.menuItems["Start Test Recording"].isEnabled)
        statusItem.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testPermissionsPaneShowsInjectedState() {
        launch(showingSettings: true)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        selectTab("Permissions")

        let microphone = settingsWindow.staticTexts["permission.microphone.status"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 10))
        XCTAssertEqual(text(of: microphone), "Granted")
        XCTAssertEqual(text(of: settingsWindow.staticTexts["permission.accessibility.status"]), "Not granted")
        XCTAssertEqual(text(of: settingsWindow.staticTexts["capability.recording"]), "Available")
        XCTAssertEqual(text(of: settingsWindow.staticTexts["capability.textInsertion"]), "Unavailable")
        XCTAssertTrue(settingsWindow.buttons["permission.accessibility.action"].exists)
    }

    @MainActor
    func testLaunchAtLoginToggleReflectsRegistration() {
        launch(showingSettings: true)
        let toggle = settingsWindow.switches["settings.launchAtLogin"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? Int, 0)

        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 1)
    }

    @MainActor
    func testSettingsWindowCanBeClosedWithoutQuitting() {
        launch(showingSettings: true)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))

        settingsWindow.buttons[XCUIIdentifierCloseWindow].click()

        XCTAssertTrue(settingsWindow.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(statusItem.exists)
    }

    // MARK: - Helpers

    @MainActor
    private func launch(showingSettings: Bool = false) {
        app.launchArguments = ["-LemmeTypeUITesting"] + (showingSettings ? ["-LemmeTypeShowSettings"] : [])
        app.launch()
    }

    @MainActor
    private var statusItem: XCUIElement {
        app.statusItems.firstMatch
    }

    @MainActor
    private var settingsWindow: XCUIElement {
        app.windows["settings"]
    }

    @MainActor
    private func selectTab(_ title: String) {
        let tab = settingsWindow.tabs[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        let selected = NSPredicate(format: "value == 1")
        let expectation = XCTNSPredicateExpectation(predicate: selected, object: tab)
        if XCTWaiter().wait(for: [expectation], timeout: 3) != .completed {
            tab.click()
        }
    }

    @MainActor
    private func text(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }
}
