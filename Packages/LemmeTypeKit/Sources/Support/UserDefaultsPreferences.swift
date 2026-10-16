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

    public var dictationShortcut: KeyboardShortcut? {
        get {
            defaults.data(forKey: Key.dictationShortcut).flatMap {
                try? JSONDecoder().decode(KeyboardShortcut.self, from: $0)
            }
        }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.dictationShortcut)
        }
    }

    public var activationMode: ActivationMode {
        get { defaults.string(forKey: Key.activationMode).flatMap(ActivationMode.init(rawValue:)) ?? .pushToTalk }
        set { defaults.set(newValue.rawValue, forKey: Key.activationMode) }
    }

    public var audioInput: AudioInputSelection {
        get {
            defaults.data(forKey: Key.audioInput).flatMap {
                try? JSONDecoder().decode(AudioInputSelection.self, from: $0)
            } ?? .systemDefault
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.audioInput)
        }
    }

    public var playsFeedbackSounds: Bool {
        get { defaults.bool(forKey: Key.playsFeedbackSounds) }
        set { defaults.set(newValue, forKey: Key.playsFeedbackSounds) }
    }

    public var dictationLanguage: String {
        get { defaults.string(forKey: Key.dictationLanguage) ?? Self.defaultDictationLanguage }
        set { defaults.set(newValue, forKey: Key.dictationLanguage) }
    }

    private enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let dictationShortcut = "dictationShortcut"
        static let activationMode = "activationMode"
        static let audioInput = "audioInput"
        static let playsFeedbackSounds = "playsFeedbackSounds"
        static let dictationLanguage = "dictationLanguage"
    }
}
