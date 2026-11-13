import Domain
import Foundation

/// Remembers that the paywall and the trial-ending notice were shown once each. Two yes-or-no values and nothing
/// about the person.
public final class UserDefaultsPaywallSeen: PaywallSeenStoring {
    private static let key = "paywallShownOnFirstLaunch"
    private static let noticeKey = "trialEndingNoticeShown"
    // `UserDefaults` is documented as thread-safe.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasSeenPaywall: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }

    public var hasSeenTrialEndingNotice: Bool {
        get { defaults.bool(forKey: Self.noticeKey) }
        set { defaults.set(newValue, forKey: Self.noticeKey) }
    }
}
