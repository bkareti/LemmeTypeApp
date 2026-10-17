import Domain
import TestSupport
import Testing

@testable import UI

@MainActor
struct ShortcutSettingsModelTests {
    private let other = KeyboardShortcut(keyCode: 0x02, modifiers: [.control, .option], keyLabel: "D")

    private struct Subject {
        let model: ShortcutSettingsModel
        let controller: FakeShortcutController
        let preferences: FakePreferences
    }

    private func make(failing: [KeyboardShortcut: ShortcutError] = [:]) -> Subject {
        let controller = FakeShortcutController(failures: failing)
        let preferences = FakePreferences()
        controller.activate()
        return Subject(
            model: ShortcutSettingsModel(controller: controller, preferences: preferences),
            controller: controller,
            preferences: preferences
        )
    }

    @Test func recordingSuspendsTheShortcutAndCancelRestoresIt() {
        let subject = make()
        let model = subject.model
        let controller = subject.controller

        model.startRecording()
        #expect(model.isRecording)
        #expect(!controller.isActive)

        model.cancelRecording()
        #expect(!model.isRecording)
        #expect(controller.isActive)
    }

    @Test func recordedShortcutIsAppliedAndPersisted() {
        let subject = make()
        let model = subject.model
        let controller = subject.controller
        let preferences = subject.preferences

        model.startRecording()
        model.recorded(other)

        #expect(controller.shortcut == other)
        #expect(preferences.dictationShortcut == other)
        #expect(model.errorMessage == nil)
        #expect(controller.isActive)
    }

    @Test func invalidShortcutShowsAnErrorAndKeepsThePreviousOne() {
        let subject = make()
        let model = subject.model
        let controller = subject.controller
        let preferences = subject.preferences

        model.startRecording()
        model.recorded(KeyboardShortcut(keyCode: 0x02, modifiers: [], keyLabel: "D"))

        #expect(model.errorMessage == ShortcutSettingsModel.message(for: .invalid(.missingModifier)))
        #expect(controller.shortcut == .defaultDictation)
        #expect(controller.isActive)
        #expect(preferences.dictationShortcut == nil)
    }

    @Test func unavailableShortcutAtLaunchIsReportedWithRecovery() {
        let subject = make(failing: [.defaultDictation: .unavailable])
        let model = subject.model

        #expect(model.isShortcutUnavailable)
        #expect(model.errorMessage == ShortcutSettingsModel.message(for: .unavailable))

        model.startRecording()
        model.recorded(other)

        #expect(!model.isShortcutUnavailable)
        #expect(model.errorMessage == nil)
    }

    @Test func modeChangeIsAppliedAndPersisted() {
        let subject = make()
        let model = subject.model
        let controller = subject.controller
        let preferences = subject.preferences

        model.setMode(.toggle)

        #expect(controller.mode == .toggle)
        #expect(preferences.activationMode == .toggle)
    }

    @Test func activityFeedbackNamesOnlyTheApp() {
        let subject = make()
        let model = subject.model

        model.record(.start(FakeTargetCapturer.textEdit))
        #expect(model.lastActivity == "Started in TextEdit")
        model.record(.cancel)
        #expect(model.lastActivity == "Cancelled")
    }

    @Test func everyErrorHasAMessage() {
        let errors: [ShortcutError] = [
            .invalid(.missingModifier), .invalid(.modifierOnly), .invalid(.reservedForCancel),
            .invalid(.systemShortcut), .unavailable, .registrationFailed(code: -1),
        ]
        #expect(Set(errors.map(ShortcutSettingsModel.message(for:))).count == errors.count)
    }

    @Test func recorderLabelsNamedAndPrintableKeys() {
        #expect(ShortcutRecorder.label(keyCode: 0x31, characters: " ") == "Space")
        #expect(ShortcutRecorder.label(keyCode: 0x02, characters: "d") == "D")
        #expect(ShortcutRecorder.label(keyCode: 0x7A, characters: nil) == "F1")
        #expect(ShortcutRecorder.label(keyCode: 0x99, characters: "") == "Key 153")
    }
}

/// Minimal in-memory `DictationShortcutControlling`.
@MainActor
final class FakeShortcutController: DictationShortcutControlling {
    private(set) var shortcut = KeyboardShortcut.defaultDictation
    private(set) var mode = ActivationMode.pushToTalk
    private(set) var registrationError: ShortcutError?
    private(set) var isActive = false
    private let failures: [KeyboardShortcut: ShortcutError]

    init(failures: [KeyboardShortcut: ShortcutError]) {
        self.failures = failures
    }

    func activate() {
        guard !isActive else { return }
        if let error = failures[shortcut] {
            registrationError = error
        } else {
            registrationError = nil
            isActive = true
        }
    }

    func suspend() { isActive = false }

    func change(to shortcut: KeyboardShortcut) throws(ShortcutError) {
        if let problem = ShortcutValidation.problem(with: shortcut) { throw .invalid(problem) }
        if let error = failures[shortcut] { throw error }
        isActive = false
        self.shortcut = shortcut
        activate()
    }

    func change(to mode: ActivationMode) { self.mode = mode }

    private(set) var editShortcut: KeyboardShortcut? = .defaultVoiceEdit
    private(set) var editRegistrationError: ShortcutError?

    func changeEdit(to shortcut: KeyboardShortcut?) throws(ShortcutError) {
        if let shortcut {
            if let problem = ShortcutValidation.problem(with: shortcut) { throw .invalid(problem) }
            if let error = failures[shortcut] { throw error }
        }
        editShortcut = shortcut
    }
}

/// E3-S5: the voice-editing shortcut.
@MainActor
struct VoiceEditShortcutSettingsTests {
    @Test func recordedEditShortcutIsAppliedAndPersisted() {
        let controller = FakeShortcutController(failures: [:])
        let preferences = FakePreferences()
        let model = ShortcutSettingsModel(controller: controller, preferences: preferences)
        let other = KeyboardShortcut(keyCode: 0x0E, modifiers: [.control, .option], keyLabel: "E")

        model.startRecordingEdit()
        model.recordedEdit(other)

        #expect(model.editShortcut == other)
        #expect(preferences.voiceEditShortcut == other)
        #expect(!model.isRecordingEdit)
    }

    @Test func invalidEditShortcutKeepsThePreviousOne() {
        let controller = FakeShortcutController(failures: [:])
        let model = ShortcutSettingsModel(controller: controller, preferences: FakePreferences())

        model.startRecordingEdit()
        model.recordedEdit(KeyboardShortcut(keyCode: 0x0E, modifiers: [], keyLabel: "E"))

        #expect(model.editShortcut == .defaultVoiceEdit)
        #expect(model.editErrorMessage != nil)
    }
}
