import Domain
import TestSupport
import Testing

@testable import Shortcuts

@MainActor
struct ActivationControllerTests {
    private let shortcut = KeyboardShortcut.defaultDictation
    private let registrar = FakeHotKeyRegistrar()
    private let capturer = FakeTargetCapturer()

    private func makeController(
        mode: ActivationMode = .pushToTalk, editShortcut: KeyboardShortcut? = nil
    ) -> (ActivationController, Recorder) {
        let controller = ActivationController(
            registrar: registrar,
            targetCapturer: capturer,
            shortcut: shortcut,
            editShortcut: editShortcut,
            mode: mode
        )
        let recorder = Recorder()
        recorder.controller = controller  // the registrar only holds the controller weakly
        controller.onCommand = { recorder.commands.append($0) }
        controller.activate()
        return (controller, recorder)
    }

    @Test func registersTheShortcutOnActivate() {
        let (controller, _) = makeController()

        #expect(controller.isRegistered)
        #expect(registrar.registeredShortcuts == [shortcut])
    }

    @Test func pressDeliversExactlyOneStartWithTheCapturedTarget() {
        let (_, recorder) = makeController()

        registrar.send(.pressed, shortcut, at: 0)
        registrar.send(.pressed, shortcut, at: 0.4)  // auto-repeat

        #expect(recorder.names == ["start"])
        #expect(recorder.startTargets.first??.bundleIdentifier == "com.apple.TextEdit")
        #expect(capturer.captureCount == 1)
    }

    @Test func pushToTalkStopsOnRelease() {
        let (_, recorder) = makeController(mode: .pushToTalk)

        registrar.send(.pressed, shortcut, at: 0)
        registrar.send(.released, shortcut, at: 2)

        #expect(recorder.names == ["start", "stop"])
    }

    @Test func toggleStopsOnSecondPress() {
        let (_, recorder) = makeController(mode: .toggle)

        registrar.send(.pressed, shortcut, at: 0)
        registrar.send(.released, shortcut, at: 0.1)
        registrar.send(.pressed, shortcut, at: 2)

        #expect(recorder.names == ["start", "stop"])
    }

    @Test func escapeIsRegisteredOnlyDuringASessionAndCancels() {
        let (controller, recorder) = makeController(mode: .toggle)
        #expect(!registrar.registeredShortcuts.contains(.cancel))

        registrar.send(.pressed, shortcut, at: 0)
        #expect(registrar.registeredShortcuts.contains(.cancel))

        registrar.send(.pressed, .cancel, at: 1)

        #expect(recorder.names == ["start", "cancel"])
        #expect(!controller.isSessionActive)
        #expect(!registrar.registeredShortcuts.contains(.cancel))
    }

    @Test func stopReleasesEscape() {
        let (_, recorder) = makeController(mode: .pushToTalk)

        registrar.send(.pressed, shortcut, at: 0)
        registrar.send(.released, shortcut, at: 1)

        #expect(recorder.names == ["start", "stop"])
        #expect(registrar.registeredShortcuts == [shortcut])
    }

    @Test func registrationFailureIsRecoverable() throws {
        registrar.failures[shortcut] = .unavailable
        let (controller, _) = makeController()
        #expect(controller.registrationError == .unavailable)
        #expect(!controller.isRegistered)

        let other = KeyboardShortcut(keyCode: 0x02, modifiers: [.control, .option], keyLabel: "D")
        try controller.change(to: other)

        #expect(controller.registrationError == nil)
        #expect(controller.shortcut == other)
        #expect(registrar.registeredShortcuts == [other])
    }

    @Test func failedChangeKeepsThePreviousShortcut() {
        let (controller, _) = makeController()
        let taken = KeyboardShortcut(keyCode: 0x02, modifiers: [.control, .option], keyLabel: "D")
        registrar.failures[taken] = .unavailable

        #expect(throws: ShortcutError.unavailable) { try controller.change(to: taken) }

        #expect(controller.shortcut == shortcut)
        #expect(registrar.registeredShortcuts == [shortcut])
    }

    @Test func invalidShortcutIsRejectedBeforeRegistration() {
        let (controller, _) = makeController()
        let count = registrar.registrationCount

        #expect(throws: ShortcutError.invalid(.missingModifier)) {
            try controller.change(to: KeyboardShortcut(keyCode: 0x02, modifiers: [], keyLabel: "D"))
        }
        #expect(registrar.registrationCount == count)
    }

    @Test func suspendReleasesTheShortcut() {
        let (controller, _) = makeController()

        controller.suspend()

        #expect(registrar.registeredShortcuts.isEmpty)
        controller.activate()
        #expect(registrar.registeredShortcuts == [shortcut])
    }

    @Test func changingModeCancelsAnActiveSession() {
        let (controller, recorder) = makeController(mode: .toggle)
        registrar.send(.pressed, shortcut, at: 0)

        controller.change(to: .pushToTalk)

        #expect(recorder.names == ["start", "cancel"])
        #expect(controller.mode == .pushToTalk)
    }

    @Test func capturesContextOnlyOnStart() throws {
        let context = try #require(
            CursorContext(precedingText: "Hi", followingText: "", selection: TextSelection(location: 2, length: 0)))
        capturer.contexts[.formatting] = .captured(context, purpose: .formatting)
        let (_, recorder) = makeController(mode: .toggle)

        registrar.send(.pressed, shortcut, at: 0)
        registrar.send(.released, shortcut, at: 0.1)
        registrar.send(.pressed, shortcut, at: 2)  // stop: nothing is read
        registrar.send(.released, shortcut, at: 2.1)

        #expect(recorder.names == ["start", "stop"])
        #expect(capturer.purposes == [.formatting])
        #expect(recorder.startTargets.first??.context.context == context)
    }

    // MARK: Voice editing (E3-S5)

    @Test func editShortcutStartsAnEditingSessionWithTheSelection() {
        let (_, recorder) = makeController(editShortcut: .defaultVoiceEdit)
        #expect(registrar.registeredShortcuts == [.defaultVoiceEdit, shortcut])

        registrar.send(.pressed, .defaultVoiceEdit, at: 0)
        registrar.send(.released, .defaultVoiceEdit, at: 1)

        #expect(recorder.names == ["edit", "stop"])
        #expect(capturer.purposes == [.editing])
    }

    @Test func theOtherShortcutIsIgnoredDuringASession() {
        let (_, recorder) = makeController(mode: .toggle, editShortcut: .defaultVoiceEdit)

        registrar.send(.pressed, shortcut, at: 0)
        registrar.send(.released, shortcut, at: 0.1)
        registrar.send(.pressed, .defaultVoiceEdit, at: 1)  // ignored: dictation is running
        registrar.send(.released, .defaultVoiceEdit, at: 1.1)
        registrar.send(.pressed, shortcut, at: 2)

        #expect(recorder.names == ["start", "stop"])
        #expect(capturer.purposes == [.formatting])
    }

    @Test func editShortcutCanBeTurnedOffAndChanged() throws {
        let (controller, _) = makeController(editShortcut: .defaultVoiceEdit)

        try controller.changeEdit(to: nil)
        #expect(registrar.registeredShortcuts == [shortcut])
        #expect(!registrar.send(.pressed, .defaultVoiceEdit, at: 0))

        let other = KeyboardShortcut(keyCode: 0x0E, modifiers: [.control, .option], keyLabel: "E")
        try controller.changeEdit(to: other)
        #expect(controller.editShortcut == other)
        #expect(registrar.registeredShortcuts.contains(other))
    }

    @Test func editShortcutCannotReuseTheDictationShortcut() {
        let (controller, _) = makeController(editShortcut: .defaultVoiceEdit)
        #expect(throws: ShortcutError.unavailable) { try controller.changeEdit(to: shortcut) }
        #expect(controller.editShortcut == .defaultVoiceEdit)
    }

    @Test func sessionEndedElsewhereAllowsANewStart() {
        let (controller, recorder) = makeController(mode: .toggle)
        registrar.send(.pressed, shortcut, at: 0)
        registrar.send(.released, shortcut, at: 0.1)

        controller.sessionEnded()
        registrar.send(.pressed, shortcut, at: 5)

        #expect(recorder.names == ["start", "start"])
    }
}

@MainActor
private final class Recorder {
    var controller: ActivationController?
    var commands: [ActivationCommand] = []

    var names: [String] {
        commands.map {
            switch $0 {
            case .start: "start"
            case .startEditing: "edit"
            case .stop: "stop"
            case .cancel: "cancel"
            }
        }
    }

    var startTargets: [ActivationTarget?] {
        commands.compactMap {
            if case .start(let target) = $0 { return target }
            return nil
        }
    }
}
