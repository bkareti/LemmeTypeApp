/// Whether LemmeType is registered to open at login, as reported by macOS.
public enum LoginItemStatus: String, Sendable {
    case enabled
    case disabled
    /// Registered, but the user must approve it in System Settings › Login Items.
    case requiresApproval
    /// macOS could not find the app to register (for example, it is not in /Applications).
    case unavailable
}
