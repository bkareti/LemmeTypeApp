import Domain

/// Returns fixed permission states. Used by unit tests, UI tests, and previews.
public struct FakePermissionChecker: PermissionChecking {
    public var statuses: [PermissionKind: PermissionStatus]

    public init(statuses: [PermissionKind: PermissionStatus] = [:]) {
        self.statuses = statuses
    }

    public func status(for permission: PermissionKind) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }
}
