import XCTest

/// How a Quick Dictation starts and ends on the iOS Simulator, against fakes that
/// play a scenario chosen by launch arguments (`IOSComposition.UITestScenario`):
/// the microphone prompt and its denial, an interruption, the time limit, leaving
/// the app, no speech, and a shortcut (E8-S4, E8-S6, E8-S7). Real calls, Siri,
/// alarms, and five-minute recordings stay in the device checklist (MA-69).
@MainActor
final class RecordingEndingsUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ scenario: [String] = []) {
        app.launchArguments = ["-LemmeTypeUITesting"] + scenario
        app.launch()
    }

    private var record: XCUIElement { app.buttons["quick.record"] }
    private var stop: XCUIElement { app.buttons["quick.stop"] }
    private var result: XCUIElement { app.staticTexts["quick.result"] }
    private var microphoneAlert: XCUIElement { app.alerts["Allow the microphone?"] }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    // MARK: Microphone permission

    func testTheFirstStartExplainsTheMicrophoneThenRecords() {
        launch(["-LemmeTypeMicrophone", "notRequested"])
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()

        XCTAssertTrue(microphoneAlert.waitForExistence(timeout: 5))
        XCTAssertFalse(stop.exists, "nothing records before the user continues")
        microphoneAlert.buttons["Continue"].tap()

        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        app.buttons["quick.cancel"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
    }

    func testNotNowRecordsNothing() {
        launch(["-LemmeTypeMicrophone", "notRequested"])
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(microphoneAlert.waitForExistence(timeout: 5))

        microphoneAlert.buttons["Not Now"].tap()

        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertFalse(stop.exists)
    }

    func testDenyingAtTheSystemPromptSaysWhyAndOffersSettings() {
        launch(["-LemmeTypeMicrophone", "notRequested", "-LemmeTypeMicrophoneAnswer", "denied"])
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(microphoneAlert.waitForExistence(timeout: 5))

        microphoneAlert.buttons["Continue"].tap()

        XCTAssertTrue(element("quick.failed").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quick.open-settings"].exists)
        XCTAssertFalse(stop.exists)
    }

    func testADeniedMicrophoneOffersSettingsAndRecordsNothing() {
        launch(["-LemmeTypeMicrophone", "denied"])
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()

        XCTAssertTrue(element("quick.failed").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quick.open-settings"].exists)
        XCTAssertFalse(stop.exists)

        app.buttons["quick.try-again"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
    }

    // MARK: Endings

    func testAnInterruptionStopsTheRecordingAndLeavesNothingToCopy() {
        // Late enough that the recording is seen first on a slow runner.
        launch(["-LemmeTypeInterruptAfter", "4"])
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 3))

        XCTAssertTrue(element("quick.failed").waitForExistence(timeout: 10))
        XCTAssertFalse(result.exists)
        XCTAssertFalse(app.buttons["quick.copy"].exists)

        app.buttons["quick.try-again"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
    }

    func testTheTimeLimitStopsTheRecordingAndTheTextIsStillReviewed() {
        launch(["-LemmeTypeRecordingLimit", "4"])
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 3))

        // Stop is never tapped: the limit ends the recording.
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        XCTAssertEqual(result.label, "hello from lemmetype")
        XCTAssertFalse(app.staticTexts["quick.copied"].exists, "the limit never copies")
    }

    func testLeavingTheAppStopsTheRecordingAndKeepsTheDictation() {
        launch()
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.state == .runningBackgroundSuspended)
        app.activate()

        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertEqual(result.label, "hello from lemmetype")
        XCTAssertFalse(stop.exists, "the recording did not continue in the background")
    }

    func testNoSpeechAsksWhatToDoAndOffersNothingToCopy() {
        launch(["-LemmeTypeRecognition", "no-speech"])
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
        stop.tap()

        XCTAssertTrue(element("quick.attention").waitForExistence(timeout: 10))
        XCTAssertFalse(result.exists)
        XCTAssertFalse(app.buttons["quick.copy"].exists)
    }

    func testDictateAgainDropsTheResultAndRecords() {
        launch()
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        Thread.sleep(forTimeInterval: 0.6)
        stop.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 10))

        app.buttons["quick.again"].tap()

        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertFalse(result.exists)
        app.buttons["quick.cancel"].tap()
    }

    // MARK: Shortcut

    func testAShortcutRequestStartsRecordingWhenTheAppOpens() {
        launch(["-LemmeTypeLaunchRequest"])

        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        app.buttons["quick.cancel"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
    }
}
