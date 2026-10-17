/// Registers system-wide hot keys. Implementations must not require Input
/// Monitoring and must not activate LemmeType or move keyboard focus.
@MainActor
public protocol HotKeyRegistering: AnyObject {
    func register(
        _ shortcut: KeyboardShortcut,
        onEvent: @escaping @MainActor (ShortcutEvent) -> Void
    ) throws(ShortcutError) -> any HotKeyRegistration
}

/// A live hot-key registration. Unregisters when `unregister()` is called.
@MainActor
public protocol HotKeyRegistration: AnyObject {
    func unregister()
}

/// Identifies the app and element that currently have keyboard focus and,
/// when the policy allows, reads context for `purpose` (E3-S2).
@MainActor
public protocol TargetCapturing: AnyObject {
    func captureTarget(purpose: ContextPurpose) -> ActivationTarget?
}

public enum ShortcutError: LemmeTypeError, Equatable {
    case invalid(ShortcutValidation.Problem)
    /// Another app or LemmeType itself already owns the combination.
    case unavailable
    /// macOS refused the registration for another reason.
    case registrationFailed(code: Int32)

    public var identifier: String {
        switch self {
        case .invalid: "shortcut.invalid"
        case .unavailable: "shortcut.unavailable"
        case .registrationFailed: "shortcut.registration-failed"
        }
    }
}

/// What the settings UI needs from the shortcut owner.
@MainActor
public protocol DictationShortcutControlling: AnyObject {
    var shortcut: KeyboardShortcut { get }
    var mode: ActivationMode { get }
    var registrationError: ShortcutError? { get }
    func activate()
    func suspend()
    func change(to shortcut: KeyboardShortcut) throws(ShortcutError)
    func change(to mode: ActivationMode)
    /// The voice-editing shortcut; `nil` when voice editing is off.
    var editShortcut: KeyboardShortcut? { get }
    var editRegistrationError: ShortcutError? { get }
    func changeEdit(to shortcut: KeyboardShortcut?) throws(ShortcutError)
}
