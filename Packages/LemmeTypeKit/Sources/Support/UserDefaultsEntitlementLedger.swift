import Domain
import Foundation

/// Keeps the latest moment the device has seen, so a clock set back does not give more time (E13-S5). One date,
/// nothing about the person.
public final class UserDefaultsEntitlementLedger: EntitlementLedgerStoring {
    private static let key = "entitlementHighWaterMark"
    // `UserDefaults` is documented as thread-safe.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var highWaterMark: Date? {
        get { defaults.object(forKey: Self.key) as? Date }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
