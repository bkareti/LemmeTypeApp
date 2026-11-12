import Domain
import Foundation

/// Remembers which cloud speech provider, and which version of its terms, the user agreed to.
public final class UserDefaultsCloudSpeechConsent: CloudSpeechConsentStoring {
    private static let providerKey = "cloudSpeechConsentedProvider"
    private static let versionKey = "cloudSpeechConsentedVersion"
    // `UserDefaults` is documented as thread-safe.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var consentedProvider: CloudSpeechProviderID? {
        get { defaults.string(forKey: Self.providerKey).map(CloudSpeechProviderID.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Self.providerKey) }
    }

    public var consentedVersion: Int? {
        get { defaults.object(forKey: Self.versionKey) as? Int }
        set { defaults.set(newValue, forKey: Self.versionKey) }
    }
}
