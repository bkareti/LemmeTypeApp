/// The authorization state of a ``PermissionKind`` as reported by macOS.
public enum PermissionStatus: String, Sendable {
    /// The user has not been asked yet, or macOS cannot tell us whether they were.
    case notDetermined
    case granted
    case denied
    /// Blocked by policy (for example a configuration profile); the user cannot change it.
    case restricted
}
