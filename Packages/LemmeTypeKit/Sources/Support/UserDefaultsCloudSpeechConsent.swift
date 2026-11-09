import Domain
import Foundation

/// Remembers which cloud speech provider the user agreed to.
public final class UserDefaultsCloudSpeechConsent: CloudSpeechConsentStoring {
    private static let key = "cloudSpeechConsentedProvider"
    // `UserDefaults` is documented as thread-safe.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var consentedProvider: CloudSpeechProviderID? {
        get { defaults.string(forKey: Self.key).map(CloudSpeechProviderID.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Self.key) }
    }
}
