import XCTest

/// Recorder state machine and overlay (E1-S6) with a fake audio source that
/// plays a tone, driven by the real dictation hot key in Toggle mode.
final class RecorderUITests: XCTestCase {
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
    func testShortcutShowsRecordingThenDoneAndHides() {
        launchInToggleMode()

        app.typeKey(" ", modifierFlags: .option)
        XCTAssertTrue(waitForOverlayState("Recording"))
        XCTAssertTrue(overlay("overlay.stop").exists)
        XCTAssertTrue(overlay("overlay.cancel").exists)

        app.typeKey(" ", modifierFlags: .option)
        XCTAssertTrue(waitForOverlayState("Done"))
        XCTAssertTrue(overlay("overlay.state").waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testOverlayCancelButtonCancels() {
        launchInToggleMode()
        app.typeKey(" ", modifierFlags: .option)
        XCTAssertTrue(waitForOverlayState("Recording"))

        overlay("overlay.cancel").click()

        XCTAssertTrue(waitForOverlayState("Cancelled"))
        XCTAssertTrue(overlay("overlay.state").waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testOverlayStopButtonStops() {
        launchInToggleMode()
        app.typeKey(" ", modifierFlags: .option)
        XCTAssertTrue(waitForOverlayState("Recording"))

        overlay("overlay.stop").click()

        XCTAssertTrue(waitForOverlayState("Done"))
    }

    @MainActor
    func testEscapeCancelsFromAnywhere() {
        launchInToggleMode()
        app.typeKey(" ", modifierFlags: .option)
        XCTAssertTrue(waitForOverlayState("Recording"))

        app.typeKey(.escape, modifierFlags: [])

        // "Cancelled" is shown for 1.5 s, often shorter than typeKey's own
        // round trip, so check the outcome: the session was cancelled and the
        // overlay is gone.
        let activity = app.windows["settings"].staticTexts["shortcut.lastActivity"]
        XCTAssertTrue(waitForText("Cancelled", in: activity))
        XCTAssertTrue(overlayPanel.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testFailureOffersARecoveryAction() {
        // Fresh install: Microphone not granted. Finish onboarding in limited
        // mode, then press the shortcut (default Push to Talk).
        app.launchArguments = ["-LemmeTypeUITesting", "-LemmeTypeFreshInstall"]
        app.launch()
        let onboarding = app.windows["onboarding"]
        XCTAssertTrue(onboarding.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            onboarding.buttons["onboarding.next"].click()
        }
        onboarding.buttons["onboarding.done"].click()
        XCTAssertTrue(onboarding.waitForNonExistence(timeout: 5))

        app.typeKey(" ", modifierFlags: .option)

        XCTAssertTrue(waitForOverlayState("Couldn’t record"))
        XCTAssertTrue(overlay("overlay.message").exists)
        let action = overlay("overlay.action")
        XCTAssertEqual(action.label, "Open Permissions")
        action.click()

        XCTAssertTrue(overlay("overlay.state").waitForNonExistence(timeout: 5))
        let permissionsTab = app.windows["settings"].tabs["Permissions"]
        XCTAssertTrue(permissionsTab.waitForExistence(timeout: 5))
        XCTAssertEqual(permissionsTab.value as? Int, 1)
    }

    // MARK: - Helpers

    /// Launches with Settings open and switches the shortcut to Toggle mode.
    @MainActor
    private func launchInToggleMode() {
        app.launchArguments = ["-LemmeTypeUITesting", "-LemmeTypeShowSettings"]
        app.launch()
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings window missing after launch")
        let tab = settings.tabs["Shortcut"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        let toggle = settings.radioButtons["Toggle — press to start and stop"]
        if !toggle.waitForExistence(timeout: 3) {
            tab.click()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
    }

    /// The overlay panel is exposed as a dialog. Queries are scoped to it: an
    /// app-wide `descendants(matching: .any)` search walks every window and
    /// menu on each poll and can stall the app's main run loop.
    @MainActor
    private var overlayPanel: XCUIElement { app.dialogs["recording-overlay"] }

    @MainActor
    private func overlay(_ identifier: String) -> XCUIElement {
        identifier == "overlay.state" || identifier == "overlay.message"
            ? overlayPanel.staticTexts[identifier] : overlayPanel.buttons[identifier]
    }

    @MainActor
    private func waitForText(_ expected: String, in element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if element.exists, (element.value as? String) == expected || element.label == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    @MainActor
    private func waitForOverlayState(_ expected: String) -> Bool {
        let element = overlay("overlay.state")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if element.exists {
                let text = (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
                if text == expected { return true }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }
}
