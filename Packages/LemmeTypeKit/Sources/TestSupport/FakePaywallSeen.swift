import Domain
import Synchronization

/// Remembers in memory whether the paywall and the trial-ending notice were shown.
public final class FakePaywallSeen: PaywallSeenStoring {
    private let value: Mutex<[Bool]>

    public init(_ seen: Bool = false, noticeSeen: Bool = false) {
        value = Mutex([seen, noticeSeen])
    }

    public var hasSeenPaywall: Bool {
        get { value.withLock { $0[0] } }
        set { value.withLock { $0[0] = newValue } }
    }

    public var hasSeenTrialEndingNotice: Bool {
        get { value.withLock { $0[1] } }
        set { value.withLock { $0[1] = newValue } }
    }
}
