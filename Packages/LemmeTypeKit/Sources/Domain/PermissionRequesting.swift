/// Asks macOS for permissions and opens the matching System Settings pane.
///
/// Callers must show their own explanation first; these methods may show a
/// system prompt immediately.
public protocol PermissionRequesting: Sendable {
    /// Shows the Microphone prompt if the user has not been asked, and returns
    /// the resulting status. Never re-prompts after a decision.
    func requestMicrophoneAccess() async -> PermissionStatus

    /// Adds LemmeType to the Accessibility list and shows the system prompt that
    /// leads to System Settings. Trust is granted asynchronously by the user.
    func requestAccessibilityAccess()

    /// Opens System Settings › Privacy & Security at the pane for `permission`.
    func openSystemSettings(for permission: PermissionKind)
}
