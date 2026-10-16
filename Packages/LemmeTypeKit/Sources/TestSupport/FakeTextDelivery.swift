import Domain
import Synchronization

/// Records delivered text instead of touching other apps or the clipboard.
public final class FakeTextDelivery: TextDelivering, TextCopying {
    private struct State {
        var outcome: DeliveryOutcome
        var delivered: [String] = []
        var targets: [String?] = []
        var copied: [String] = []
    }

    private let state: Mutex<State>

    public init(outcome: DeliveryOutcome = .delivered(.accessibility)) {
        state = Mutex(State(outcome: outcome))
    }

    public var delivered: [String] { state.withLock { $0.delivered } }
    /// Application names of the targets text was delivered to.
    public var targets: [String?] { state.withLock { $0.targets } }
    public var copied: [String] { state.withLock { $0.copied } }

    public func setOutcome(_ outcome: DeliveryOutcome) {
        state.withLock { $0.outcome = outcome }
    }

    public func deliver(_ text: String, to target: ActivationTarget?) async -> DeliveryOutcome {
        state.withLock { state in
            if case .delivered = state.outcome {
                state.delivered.append(text)
                state.targets.append(target?.applicationName)
            }
            return state.outcome
        }
    }

    public func copy(_ text: String) async {
        state.withLock { $0.copied.append(text) }
    }
}
