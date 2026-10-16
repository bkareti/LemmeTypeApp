import Domain
import Support

/// Owns the dictation shortcut: registers it, interprets presses for the
/// current mode, captures the target at start, and arms Escape as cancel only
/// while a session is active.
@MainActor
public final class ActivationController: DictationShortcutControlling {
    public private(set) var shortcut: KeyboardShortcut
    public private(set) var mode: ActivationMode
    /// Set when the current shortcut could not be registered.
    public private(set) var registrationError: ShortcutError?
    public var isSessionActive: Bool { interpreter.isSessionActive }
    public var isRegistered: Bool { registration != nil }

    /// Receives start/stop/cancel decisions. E1-S6 connects the recorder here.
    public var onCommand: @MainActor (ActivationCommand) -> Void = { _ in }

    private let registrar: any HotKeyRegistering
    private let targetCapturer: any TargetCapturing
    private var interpreter: ActivationInterpreter
    private var registration: (any HotKeyRegistration)?
    private var cancelRegistration: (any HotKeyRegistration)?

    public init(
        registrar: any HotKeyRegistering,
        targetCapturer: any TargetCapturing,
        shortcut: KeyboardShortcut,
        mode: ActivationMode
    ) {
        self.registrar = registrar
        self.targetCapturer = targetCapturer
        self.shortcut = shortcut
        self.mode = mode
        self.interpreter = ActivationInterpreter(mode: mode)
    }

    /// Registers the current shortcut. Failure is kept in ``registrationError``
    /// so the UI can offer a different shortcut.
    public func activate() {
        guard registration == nil else { return }
        do {
            registration = try registrar.register(shortcut) { [weak self] event in
                self?.handle(event)
            }
            registrationError = nil
            Log.shortcuts.info("Dictation shortcut registered")
        } catch {
            registrationError = error
        }
    }

    /// Releases the shortcut, e.g. while the user records a new one.
    public func suspend() {
        cancelSession()
        registration?.unregister()
        registration = nil
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
    }

    /// Cancels the active session, if any (Escape, menu, or overlay).
    public func cancelSession() {
        guard interpreter.isSessionActive else { return }
        endSession()
        Log.shortcuts.info("Dictation cancelled")
        onCommand(.cancel)
    }

    /// The session ended on its own (completed or failed); no command is sent.
    public func sessionEnded() {
        endSession()
    }

    private func handle(_ event: ShortcutEvent) {
        switch interpreter.handle(event) {
        case .start:
            let target = targetCapturer.captureTarget()
            armCancel()
            Log.shortcuts.info("Dictation start (\(self.mode.rawValue, privacy: .public))")
            onCommand(.start(target))
        case .stop:
            disarmCancel()
            Log.shortcuts.info("Dictation stop")
            onCommand(.stop)
        case .ignore:
            break
        }
    }

    private func endSession() {
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
