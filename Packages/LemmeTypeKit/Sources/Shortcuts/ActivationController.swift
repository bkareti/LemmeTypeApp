import Domain
import Support

/// Owns the dictation and voice-editing shortcuts: registers them, interprets
/// presses for the current mode, captures the target (and context) at start,
/// and arms Escape as cancel only while a session is active. Only one session
/// runs at a time; the other shortcut is ignored until it ends.
@MainActor
public final class ActivationController: DictationShortcutControlling {
    public private(set) var shortcut: KeyboardShortcut
    public private(set) var mode: ActivationMode
    /// Set when the current shortcut could not be registered.
    public private(set) var registrationError: ShortcutError?
    /// The voice-editing shortcut; `nil` when voice editing is off (E3-S5).
    public private(set) var editShortcut: KeyboardShortcut?
    public private(set) var editRegistrationError: ShortcutError?
    public var isSessionActive: Bool { interpreter.isSessionActive }
    public var isRegistered: Bool { registration != nil }

    /// Receives start/stop/cancel decisions. E1-S6 connects the recorder here.
    public var onCommand: @MainActor (ActivationCommand) -> Void = { _ in }

    private let registrar: any HotKeyRegistering
    private let targetCapturer: any TargetCapturing
    private var interpreter: ActivationInterpreter
    private var registration: (any HotKeyRegistration)?
    private var editRegistration: (any HotKeyRegistration)?
    /// Which shortcut started the current session.
    private var activePurpose: ContextPurpose?
    private var cancelRegistration: (any HotKeyRegistration)?
    private let diagnostics: any DiagnosticsRecording

    public init(
        registrar: any HotKeyRegistering,
        targetCapturer: any TargetCapturing,
        shortcut: KeyboardShortcut,
        editShortcut: KeyboardShortcut? = nil,
        mode: ActivationMode,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.registrar = registrar
        self.targetCapturer = targetCapturer
        self.diagnostics = diagnostics
        self.shortcut = shortcut
        self.editShortcut = editShortcut
        self.mode = mode
        self.interpreter = ActivationInterpreter(mode: mode)
    }

    /// Registers the current shortcut. Failure is kept in ``registrationError``
    /// so the UI can offer a different shortcut.
    public func activate() {
        activateEdit()
        guard registration == nil else { return }
        do {
            registration = try registrar.register(shortcut) { [weak self] event in
                self?.handle(event, purpose: .formatting)
            }
            registrationError = nil
            Log.shortcuts.info("Dictation shortcut registered")
            diagnostics.record(.shortcut, "shortcut.registered")
        } catch {
            registrationError = error
            diagnostics.record(.shortcut, "shortcut.registration-failed", ["error": .id(error.identifier)])
        }
    }

    /// Releases the shortcuts, e.g. while the user records a new one.
    public func suspend() {
        cancelSession()
        registration?.unregister()
        registration = nil
        editRegistration?.unregister()
        editRegistration = nil
    }

    private func activateEdit() {
        guard editRegistration == nil, let editShortcut else { return }
        do {
            editRegistration = try registrar.register(editShortcut) { [weak self] event in
                self?.handle(event, purpose: .editing)
            }
            editRegistrationError = nil
            diagnostics.record(.shortcut, "shortcut.edit-registered")
        } catch {
            editRegistrationError = error
            diagnostics.record(.shortcut, "shortcut.edit-registration-failed", ["error": .id(error.identifier)])
        }
    }

    /// Sets (or, with `nil`, removes) the voice-editing shortcut. On failure
    /// the previous one stays registered and the error is thrown.
    public func changeEdit(to newShortcut: KeyboardShortcut?) throws(ShortcutError) {
        if let newShortcut {
            if let problem = ShortcutValidation.problem(with: newShortcut) { throw .invalid(problem) }
            if newShortcut == shortcut { throw .unavailable }
        }
        if activePurpose == .editing { cancelSession() }
        let previous = editShortcut
        editRegistration?.unregister()
        editRegistration = nil
        editRegistrationError = nil
        editShortcut = newShortcut
        activateEdit()
        if let error = editRegistrationError {
            editShortcut = previous
            activateEdit()
            throw error
        }
    }

    /// Validates and registers `newShortcut`. On failure the previous shortcut
    /// stays registered and the error is thrown.
    public func change(to newShortcut: KeyboardShortcut) throws(ShortcutError) {
        if let problem = ShortcutValidation.problem(with: newShortcut) {
            throw .invalid(problem)
        }
        let previous = shortcut
        suspend()
        shortcut = newShortcut
        activate()
        if let error = registrationError {
            shortcut = previous
            activate()
            throw error
        }
    }

    public func change(to newMode: ActivationMode) {
        cancelSession()
        mode = newMode
        interpreter.mode = newMode
        diagnostics.record(.shortcut, "shortcut.mode", ["mode": .id(newMode.rawValue)])
    }

    /// Cancels the active session, if any (Escape, menu, or overlay).
    public func cancelSession() {
        guard interpreter.isSessionActive else { return }
        endSession()
        Log.shortcuts.info("Dictation cancelled")
        diagnostics.record(.shortcut, "activation.cancel")
        onCommand(.cancel)
    }

    /// The session ended on its own (completed or failed); no command is sent.
    public func sessionEnded() {
        endSession()
    }

    private func handle(_ event: ShortcutEvent, purpose: ContextPurpose) {
        // While one shortcut's session runs, the other one is ignored.
        if interpreter.isSessionActive, activePurpose != purpose { return }
        switch interpreter.handle(event) {
        case .start:
            activePurpose = purpose
            // The only moment context is read (ADR 0017).
            let target = targetCapturer.captureTarget(purpose: purpose)
            armCancel()
            Log.shortcuts.info(
                "Start (\(self.mode.rawValue, privacy: .public), \(purpose.rawValue, privacy: .public))")
            diagnostics.record(
                .shortcut, "activation.start",
                [
                    "mode": .id(mode.rawValue), "purpose": .id(purpose.rawValue),
                    "hasFocusedElement": .flag(target?.focusedElement != nil),
                    "context": .id(target?.context.identifier ?? ContextCapture.notRequested.identifier),
                ])
            onCommand(purpose == .editing ? .startEditing(target) : .start(target))
        case .stop:
            disarmCancel()
            Log.shortcuts.info("Dictation stop")
            diagnostics.record(.shortcut, "activation.stop")
            onCommand(.stop)
        case .ignore:
            break
        }
    }

    private func endSession() {
        activePurpose = nil
        interpreter.sessionEnded()
        disarmCancel()
    }

    private func armCancel() {
        do {
            cancelRegistration = try registrar.register(.cancel) { [weak self] event in
                if event.kind == .pressed { self?.cancelSession() }
            }
        } catch {
            // Cancel stays available from the menu and overlay.
            Log.shortcuts.error("Escape could not be registered: \(error.identifier, privacy: .public)")
        }
    }

    private func disarmCancel() {
        cancelRegistration?.unregister()
        cancelRegistration = nil
    }
}
