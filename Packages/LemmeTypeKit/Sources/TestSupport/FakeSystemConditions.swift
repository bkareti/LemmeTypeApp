import Domain
import Foundation
import Synchronization

/// Scriptable system conditions for tests and UI tests.
public final class FakeSystemConditions: SystemConditionsMonitoring {
    private struct State {
        var conditions: SystemConditions
        var subscribers: [UUID: AsyncStream<SystemConditions>.Continuation] = [:]
    }

    private let state: Mutex<State>

    public init(_ conditions: SystemConditions = .nominal) {
        state = Mutex(State(conditions: conditions))
    }

    public var current: SystemConditions { state.withLock { $0.conditions } }

    public func changes() -> AsyncStream<SystemConditions> {
        let (stream, continuation) = AsyncStream.makeStream(of: SystemConditions.self)
        let id = UUID()
        state.withLock { $0.subscribers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        return stream
    }

    /// Changes the conditions and notifies subscribers.
    public func set(_ conditions: SystemConditions) {
        let subscribers = state.withLock { state in
            state.conditions = conditions
            return Array(state.subscribers.values)
        }
        for subscriber in subscribers {
            subscriber.yield(conditions)
        }
    }
}
