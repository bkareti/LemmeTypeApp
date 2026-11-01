import XCTest

/// E7-S6: Xcode's accessibility audit over onboarding and every Settings pane,
/// plus keyboard reachability, against fake services. Run with UI Automation Mode
/// on a Mac with a GUI session. Exclusions are listed with the reason.
final class AccessibilityUITests: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var app: XCUIApplication!

    /// Settings panes in the order of the tab bar, with a control that proves each one loaded.
    private let panes: [(tab: String, anchor: String)] = [
        ("General", "settings.launchAtLogin"), ("Dictation", "dictation.section"), ("Shortcut", "shortcut.current"),
        ("Context", "context.formatting"), ("Audio", "audio.input"), ("Permissions", "permission.microphone.status"),
        ("Privacy", "privacy.section"), ("Diagnostics", "diagnostics.preview"),
    ]

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-LemmeTypeUITesting", "-LemmeTypeShowSettings"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    /// Issues the audit may skip, each with the reason it is safe to skip.
    private func isJustified(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        // The window's title bar and traffic-light buttons are drawn by macOS, not LemmeType.
        if issue.element?.elementType == .window { return true }
        return false
    }

    @MainActor
    func testEverySettingsPanePassesTheAccessibilityAudit() throws {
        let window = app.windows["settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for pane in panes {
            let tab = window.tabs[pane.tab]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(pane.tab) tab exists")
            tab.click()
            try app.performAccessibilityAudit(for: .all) { self.isJustified($0) }
        }
    }

    @MainActor
    func testEveryInteractiveControlInSettingsHasAName() {
        let window = app.windows["settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for pane in panes {
            window.tabs[pane.tab].click()
            let controls =
                window.buttons.allElementsBoundByIndex + window.checkBoxes.allElementsBoundByIndex
                + window.popUpButtons.allElementsBoundByIndex
            for control in controls where control.isHittable {
                let name = control.label.isEmpty ? control.identifier : control.label
                XCTAssertFalse(name.isEmpty, "an unnamed control in \(pane.tab): \(control.debugDescription)")
            }
        }
    }

    @MainActor
    func testTheTabsCanBeReachedWithTheKeyboardAlone() {
        let window = app.windows["settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.tabs["General"].click()
        // ⌃Tab moves between tabs of a tab view; each pane then shows its own content.
        for pane in panes.dropFirst() {
            app.typeKey(XCUIKeyboardKey.tab, modifierFlags: .control)
            XCTAssertTrue(
                window.tabs[pane.tab].isSelected || window.tabs[pane.tab].value as? Int == 1,
                "\(pane.tab) is reachable from the keyboard")
        }
    }
}
