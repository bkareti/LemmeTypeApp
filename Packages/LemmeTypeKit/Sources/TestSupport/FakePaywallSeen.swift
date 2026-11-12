import Domain
import Synchronization

/// Remembers in memory whether the paywall was shown.
public final class FakePaywallSeen: PaywallSeenStoring {
    private let value: Mutex<Bool>

    public init(_ seen: Bool = false) {
        value = Mutex(seen)
    }

    public var hasSeenPaywall: Bool {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}
