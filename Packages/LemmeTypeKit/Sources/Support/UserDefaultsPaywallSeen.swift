import Domain
import Foundation

/// Remembers that the paywall was shown once. It holds one yes or no and nothing about the person.
public final class UserDefaultsPaywallSeen: PaywallSeenStoring {
    private static let key = "paywallShownOnFirstLaunch"
    // `UserDefaults` is documented as thread-safe.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasSeenPaywall: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
