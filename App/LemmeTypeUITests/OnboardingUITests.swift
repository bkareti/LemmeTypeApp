import XCTest

/// Permission onboarding (E1-S3) against fake permissions. Requests in the
/// fake succeed immediately, standing in for the user's answer.
final class OnboardingUITests: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-LemmeTypeUITesting", "-LemmeTypeFreshInstall"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    @MainActor
    func testFreshInstallExplainsEachPermissionBeforeRequestingIt() {
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertEqual(text(of: title), "Welcome to LemmeType")

        window.buttons["onboarding.next"].click()
        XCTAssertEqual(text(of: title), "Microphone")
        XCTAssertEqual(text(of: window.staticTexts["permission.microphone.status"]), "Not requested")

        window.buttons["permission.microphone.action"].click()
        XCTAssertTrue(waitForText("Granted", in: window.staticTexts["permission.microphone.status"]))

        window.buttons["onboarding.next"].click()
        XCTAssertEqual(text(of: title), "Accessibility")
        XCTAssertEqual(text(of: window.staticTexts["permission.accessibility.status"]), "Not granted")

        window.buttons["permission.accessibility.action"].click()
        XCTAssertTrue(waitForText("Granted", in: window.staticTexts["permission.accessibility.status"]))

        window.buttons["onboarding.next"].click()
        XCTAssertEqual(text(of: title), "Setup summary")
        XCTAssertFalse(window.staticTexts["onboarding.limitedNote"].exists)

        window.buttons["onboarding.done"].click()
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testSetupCanFinishInLimitedState() {
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            window.buttons["onboarding.next"].click()
        }

        XCTAssertEqual(text(of: title), "Setup summary")
        XCTAssertTrue(window.staticTexts["onboarding.limitedNote"].exists)
        window.buttons["onboarding.done"].click()
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))

        let statusItem = app.statusItems.firstMatch
        statusItem.click()
        XCTAssertTrue(statusItem.menuItems["Finish Setup…"].waitForExistence(timeout: 5))
        statusItem.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Helpers

    @MainActor
    private var window: XCUIElement { app.windows["onboarding"] }

    @MainActor
    private var title: XCUIElement { window.staticTexts["onboarding.title"] }

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
