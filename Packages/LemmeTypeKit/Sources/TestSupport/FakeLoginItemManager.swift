import Domain
import Synchronization

/// In-memory login item registration with optional injected failure.
public final class FakeLoginItemManager: LoginItemManaging {
    private struct State {
        var status: LoginItemStatus
        var failsUpdates: Bool
        var openSettingsCount = 0
    }

    private let state: Mutex<State>

    public init(status: LoginItemStatus = .disabled, failsUpdates: Bool = false) {
        state = Mutex(State(status: status, failsUpdates: failsUpdates))
    }

    public var openSettingsCount: Int { state.withLock { $0.openSettingsCount } }

    public func status() -> LoginItemStatus {
        state.withLock { $0.status }
    }

    public func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        let failed = state.withLock { state -> Bool in
            guard !state.failsUpdates else { return true }
            state.status = enabled ? .enabled : .disabled
            return false
        }
        if failed { throw LoginItemError() }
    }

    public func openSystemSettings() {
        state.withLock { $0.openSettingsCount += 1 }
    }
}
