/// The authorization state of a ``PermissionKind`` as reported by macOS.
///
/// Only states macOS can actually report are used for each permission:
/// Microphone uses `notRequested`, `granted`, `denied`, `restricted`;
/// Accessibility uses `granted` and `notGranted`.
public enum PermissionStatus: String, Sendable {
    /// The user has not been asked yet.
    case notRequested
    case granted
    /// The user declined. macOS will not ask again; only System Settings can change it.
    case denied
    /// Blocked by policy (for example a configuration profile); the user cannot change it.
    case restricted
    /// Not granted, and macOS does not say whether the user was ever asked.
    case notGranted

    public var isGranted: Bool { self == .granted }
}
