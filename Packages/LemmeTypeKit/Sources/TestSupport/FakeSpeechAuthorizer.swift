import Domain
import Synchronization

/// In-memory speech-recognition authorization.
public final class FakeSpeechAuthorizer: SpeechRecognitionAuthorizing {
    private struct State {
        var status: PermissionStatus
        var answer: PermissionStatus
        var requestCount = 0
        var openedSettingsCount = 0
    }

    private let state: Mutex<State>

    public init(status: PermissionStatus = .granted, answer: PermissionStatus = .granted) {
        state = Mutex(State(status: status, answer: answer))
    }

    public var requestCount: Int { state.withLock { $0.requestCount } }
    public var openedSettingsCount: Int { state.withLock { $0.openedSettingsCount } }

    public func set(_ status: PermissionStatus) {
        state.withLock { $0.status = status }
    }

    public func status() -> PermissionStatus {
        state.withLock { $0.status }
    }

    public func requestAuthorization() async -> PermissionStatus {
        state.withLock { state in
            guard state.status == .notRequested else { return state.status }
            state.requestCount += 1
            state.status = state.answer
            return state.answer
        }
    }

    public func openSystemSettings() {
        state.withLock { $0.openedSettingsCount += 1 }
    }
}
