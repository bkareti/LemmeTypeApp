import Domain
import Foundation

/// `AppPreferences` backed by `UserDefaults`. Stores flags only — never
/// dictated content.
public final class UserDefaultsPreferences: AppPreferences, @unchecked Sendable {
    // UserDefaults is documented as thread-safe; this type adds no mutable state.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    private enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }
}
