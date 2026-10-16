import XCTest

/// Audio input selection and level test (E1-S5) against a fake audio source
/// that plays a quiet tone while running. No microphone is used.
final class AudioUITests: XCTestCase {
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
    func testListsSystemDefaultAndConnectedInputs() {
        openAudioPane()
        let picker = window.popUpButtons["audio.input"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()

        XCTAssertTrue(app.menuItems["System Default"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["UI Test Microphone"].exists)
        app.menuItems["UI Test USB Microphone"].click()

        XCTAssertTrue(waitForValue("UI Test USB Microphone", in: picker))
    }

    @MainActor
    func testMicrophoneTestShowsLevelAndStops() {
        openAudioPane()
        let meter = window.descendants(matching: .any)["audio.level"]
        XCTAssertTrue(meter.waitForExistence(timeout: 5))
        // The meter's numeric value is the level; VoiceOver reads a coarse
        // description ("Sound detected") instead of the changing number.
        XCTAssertTrue(waitForLevel(in: meter) { $0 == 0 })

        window.buttons["audio.test"].click()
        XCTAssertTrue(waitForLevel(in: meter) { $0 > 0.1 })

        window.buttons["audio.test"].click()
        XCTAssertTrue(waitForLevel(in: meter) { $0 == 0 })
    }

    // MARK: - Helpers

    @MainActor private var window: XCUIElement { app.windows["settings"] }

    @MainActor
    private func openAudioPane() {
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let tab = window.tabs["Audio"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 1"), object: tab)
        if XCTWaiter().wait(for: [selected], timeout: 3) != .completed {
            tab.click()
        }
    }

    @MainActor
    private func waitForLevel(in element: XCUIElement, _ condition: (Double) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if element.exists, let value = element.value as? NSNumber, condition(value.doubleValue) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    @MainActor
    private func waitForValue(_ expected: String, in element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if element.exists && (element.value as? String) == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }
}
