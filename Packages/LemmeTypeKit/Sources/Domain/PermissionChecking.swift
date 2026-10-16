/// Reads the current state of a permission without prompting the user.
public protocol PermissionChecking: Sendable {
    func status(for permission: PermissionKind) -> PermissionStatus
}
