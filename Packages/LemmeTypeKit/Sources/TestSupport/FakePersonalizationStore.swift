import Domain
import Synchronization

/// In-memory `PersonalizationStoring` that counts saves and can fail on demand.
public final class FakePersonalizationStore: PersonalizationStoring {
    private struct State {
        var library: PersonalizationLibrary
        var issue: PersonalizationError?
        var saveError: PersonalizationError?
        var saveCount = 0
        var deleteCount = 0
    }

    private let state: Mutex<State>

    public init(library: PersonalizationLibrary = .empty, issue: PersonalizationError? = nil) {
        state = Mutex(State(library: library, issue: issue))
    }

    public var library: PersonalizationLibrary { state.withLock { $0.library } }
    public var saveCount: Int { state.withLock { $0.saveCount } }
    public var deleteCount: Int { state.withLock { $0.deleteCount } }

    public func failSaves(with error: PersonalizationError?) {
        state.withLock { $0.saveError = error }
    }

    public func load() async -> PersonalizationLoad {
        state.withLock { state in
            defer { state.issue = nil }
            return PersonalizationLoad(library: state.library, issue: state.issue)
        }
    }

    public func save(_ library: PersonalizationLibrary) async throws(PersonalizationError) {
        let error = state.withLock { state -> PersonalizationError? in
            if let error = state.saveError { return error }
            state.library = library
            state.saveCount += 1
            return nil
        }
        if let error { throw error }
    }

    public func deleteAll() async throws(PersonalizationError) {
        state.withLock {
            $0.library = .empty
            $0.deleteCount += 1
        }
    }
}
