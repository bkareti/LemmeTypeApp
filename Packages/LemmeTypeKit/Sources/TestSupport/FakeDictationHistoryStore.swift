import Domain
import Synchronization

/// In-memory `DictationHistoryStoring` that counts calls and can fail on demand.
public final class FakeDictationHistoryStore: DictationHistoryStoring {
    private struct State {
        var history: DictationHistory
        var issue: DictationHistoryError?
        var saveError: DictationHistoryError?
        var loadCount = 0
        var saveCount = 0
        var deleteCount = 0
    }

    private let state: Mutex<State>

    public init(history: DictationHistory = .empty, issue: DictationHistoryError? = nil) {
        state = Mutex(State(history: history, issue: issue))
    }

    public var history: DictationHistory { state.withLock { $0.history } }
    public var loadCount: Int { state.withLock { $0.loadCount } }
    public var saveCount: Int { state.withLock { $0.saveCount } }
    public var deleteCount: Int { state.withLock { $0.deleteCount } }

    public func failSaves(with error: DictationHistoryError?) {
        state.withLock { $0.saveError = error }
    }

    public func load() async -> DictationHistoryLoad {
        state.withLock { state in
            state.loadCount += 1
            defer { state.issue = nil }
            return DictationHistoryLoad(history: state.history, issue: state.issue)
        }
    }

    public func save(_ history: DictationHistory) async throws(DictationHistoryError) {
        let error = state.withLock { state -> DictationHistoryError? in
            if let error = state.saveError { return error }
            state.history = history
            state.saveCount += 1
            return nil
        }
        if let error { throw error }
    }

    public func deleteAll() async throws(DictationHistoryError) {
        state.withLock {
            $0.history = .empty
            $0.deleteCount += 1
        }
    }
}
