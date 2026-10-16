import XCTest

final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsInjectedPermissionAndDeviceState() {
        let app = XCUIApplication()
        app.launchArguments = ["-LemmeTypeUITesting"]
        app.launch()

        let microphone = app.staticTexts["permission.microphone.status"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 10))
        XCTAssertEqual(text(of: microphone), "Granted")
        XCTAssertEqual(text(of: app.staticTexts["permission.accessibility.status"]), "Not granted")
        XCTAssertEqual(text(of: app.staticTexts["audio.inputDeviceCount"]), "2")
    }

    @MainActor
    private func text(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }
}
