import Domain
import Observation
import Support

/// The single source of permission state for every screen. Reads only what
/// macOS reports and refreshes on demand (app activation, polling while a
/// permission screen is visible) because Accessibility has no change notification.
@MainActor
@Observable
public final class PermissionsModel {
    public enum Action: Equatable, Sendable {
        /// Show the system prompt (only offered when it will actually appear).
        case request
        /// The decision can only be changed in System Settings.
        case openSystemSettings
    }

    public private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    /// Accessibility has been requested this session; a second request would
    /// only repeat the same system alert, so the UI offers System Settings instead.
    public private(set) var hasRequestedAccessibility = false

    private let checker: any PermissionChecking
    private let requester: any PermissionRequesting

    public init(checker: any PermissionChecking, requester: any PermissionRequesting) {
        self.checker = checker
        self.requester = requester
        refresh()
    }

    public func status(for permission: PermissionKind) -> PermissionStatus {
        statuses[permission] ?? checker.status(for: permission)
    }

    public func isAvailable(_ capability: Capability) -> Bool {
        status(for: capability.requiredPermission).isGranted
    }

    public var allGranted: Bool {
        PermissionKind.allCases.allSatisfy { status(for: $0).isGranted }
    }

    public func action(for permission: PermissionKind) -> Action? {
        switch (permission, status(for: permission)) {
        case (_, .granted), (_, .restricted):
            nil
        case (.microphone, .notRequested):
            .request
        case (.accessibility, .notGranted), (.accessibility, .notRequested):
            hasRequestedAccessibility ? .openSystemSettings : .request
        case (_, .denied), (_, .notGranted), (_, .notRequested):
            .openSystemSettings
        }
    }

    public func refresh() {
        for permission in PermissionKind.allCases {
            let new = checker.status(for: permission)
            if let old = statuses[permission], old != new {
                Log.permissions.info(
                    "\(permission.rawValue, privacy: .public) changed \(old.rawValue, privacy: .public) → \(new.rawValue, privacy: .public)"
                )
            }
            statuses[permission] = new
        }
    }

    /// Performs the current ``action(for:)`` for `permission`.
    public func perform(_ action: Action, for permission: PermissionKind) async {
        switch (action, permission) {
        case (.request, .microphone):
            statuses[.microphone] = await requester.requestMicrophoneAccess()
        case (.request, .accessibility):
            hasRequestedAccessibility = true
            requester.requestAccessibilityAccess()
        case (.openSystemSettings, _):
            requester.openSystemSettings(for: permission)
        }
        refresh()
    }
}
