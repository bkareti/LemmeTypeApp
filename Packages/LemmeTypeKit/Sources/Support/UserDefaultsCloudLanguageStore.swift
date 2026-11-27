import Domain
import Foundation

/// Keeps the last list of Cloud speech languages the gateway gave (E12-S7), so the Language menu
/// is right before the gateway is asked again. Language codes only.
public final class UserDefaultsCloudLanguageStore: CloudLanguageStoring {
    private static let key = "cloudSpeechLanguages"
    // `UserDefaults` is documented as thread-safe.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var cloudLanguages: [String]? {
        get { defaults.stringArray(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
