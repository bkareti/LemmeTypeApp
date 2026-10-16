import Domain
import Synchronization

/// In-memory permission system: reports configurable statuses and simulates
/// the user's answer to requests. Used by unit tests, UI tests, and previews.
public final class FakePermissions: PermissionChecking, PermissionRequesting {
    private struct State {
        var statuses: [PermissionKind: PermissionStatus]
        var microphoneAnswer: PermissionStatus
        var grantsAccessibilityOnRequest: Bool
        var microphoneRequestCount = 0
        var accessibilityRequestCount = 0
        var openedSettings: [PermissionKind] = []
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - statuses: Initial statuses. Missing Microphone defaults to `notRequested`,
    ///     missing Accessibility to `notGranted`.
    ///   - microphoneAnswer: The status a Microphone prompt resolves to.
    ///   - grantsAccessibilityOnRequest: Whether an Accessibility request immediately trusts the app.
    public init(
        statuses: [PermissionKind: PermissionStatus] = [:],
        microphoneAnswer: PermissionStatus = .granted,
        grantsAccessibilityOnRequest: Bool = false
    ) {
        state = Mutex(
            State(
                statuses: statuses,
                microphoneAnswer: microphoneAnswer,
                grantsAccessibilityOnRequest: grantsAccessibilityOnRequest
            ))
    }

    public var microphoneRequestCount: Int { state.withLock { $0.microphoneRequestCount } }
    public var accessibilityRequestCount: Int { state.withLock { $0.accessibilityRequestCount } }
    public var openedSettings: [PermissionKind] { state.withLock { $0.openedSettings } }

    /// Simulates the user changing a permission in System Settings.
    public func set(_ status: PermissionStatus, for permission: PermissionKind) {
        state.withLock { $0.statuses[permission] = status }
    }

    public func status(for permission: PermissionKind) -> PermissionStatus {
        state.withLock { Self.status(for: permission, in: $0) }
    }

    public func requestMicrophoneAccess() async -> PermissionStatus {
        state.withLock { state in
            guard Self.status(for: .microphone, in: state) == .notRequested else {
                return Self.status(for: .microphone, in: state)
            }
            state.microphoneRequestCount += 1
            state.statuses[.microphone] = state.microphoneAnswer
            return state.microphoneAnswer
        }
    }

    public func requestAccessibilityAccess() {
        state.withLock { state in
            state.accessibilityRequestCount += 1
            if state.grantsAccessibilityOnRequest {
                state.statuses[.accessibility] = .granted
            }
        }
    }

    public func openSystemSettings(for permission: PermissionKind) {
        state.withLock { $0.openedSettings.append(permission) }
    }

    private static func status(for permission: PermissionKind, in state: State) -> PermissionStatus {
        state.statuses[permission] ?? (permission == .microphone ? .notRequested : .notGranted)
    }
}
