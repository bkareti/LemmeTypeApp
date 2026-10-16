/// Registers and unregisters LemmeType as a login item.
public protocol LoginItemManaging: Sendable {
    /// The current registration as reported by the system, never a cached preference.
    func status() -> LoginItemStatus
    func setEnabled(_ enabled: Bool) throws(LoginItemError)
    /// Opens System Settings › General › Login Items.
    func openSystemSettings()
}

/// Registration with macOS failed.
public struct LoginItemError: LemmeTypeError, Equatable {
    public let identifier = "lifecycle.login-item-update-failed"

    public init() {}
}
