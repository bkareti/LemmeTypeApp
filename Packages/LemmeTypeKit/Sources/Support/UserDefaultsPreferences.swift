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

    public var writingMode: WritingMode {
        get { defaults.string(forKey: Key.writingMode).flatMap(WritingMode.init(rawValue:)) ?? .exact }
        set { defaults.set(newValue.rawValue, forKey: Key.writingMode) }
    }

    public var dictationMode: DictationModeID {
        get {
            defaults.string(forKey: Key.dictationMode).map(DictationModeID.init(rawValue:))
                ?? DictationMode.builtIn(for: writingMode).id
        }
        set { defaults.set(newValue.rawValue, forKey: Key.dictationMode) }
    }

    public var selectedEngine: RecognitionEngineID? {
        get { defaults.string(forKey: Key.selectedEngine).map(RecognitionEngineID.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Key.selectedEngine) }
    }

    public var fallsBackToReadyEngine: Bool {
        get { defaults.bool(forKey: Key.fallsBackToReadyEngine) }
        set { defaults.set(newValue, forKey: Key.fallsBackToReadyEngine) }
    }

    public var clipboardFallback: ClipboardFallbackPolicy {
        get {
            defaults.data(forKey: Key.clipboardFallback).flatMap {
                try? JSONDecoder().decode(ClipboardFallbackPolicy.self, from: $0)
            } ?? .default
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.clipboardFallback)
        }
    }

    public var usesFormattingContext: Bool {
        get { defaults.bool(forKey: Key.usesFormattingContext) }
        set { defaults.set(newValue, forKey: Key.usesFormattingContext) }
    }

    public var allowsVoiceEditing: Bool {
        get { defaults.object(forKey: Key.allowsVoiceEditing) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.allowsVoiceEditing) }
    }

    public var voiceEditShortcut: KeyboardShortcut? {
        get {
            defaults.data(forKey: Key.voiceEditShortcut).flatMap {
                try? JSONDecoder().decode(KeyboardShortcut.self, from: $0)
            }
        }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.voiceEditShortcut)
        }
    }

    /// Bundle identifiers only.
    public var contextExcludedApplications: [String] {
        get { defaults.stringArray(forKey: Key.contextExcludedApplications) ?? [] }
        set { defaults.set(newValue, forKey: Key.contextExcludedApplications) }
    }

    private enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let dictationShortcut = "dictationShortcut"
        static let activationMode = "activationMode"
        static let audioInput = "audioInput"
        static let playsFeedbackSounds = "playsFeedbackSounds"
        static let dictationLanguage = "dictationLanguage"
        static let writingMode = "writingMode"
        static let dictationMode = "dictationMode"
        static let selectedEngine = "selectedEngine"
        static let clipboardFallback = "clipboardFallback"
        static let fallsBackToReadyEngine = "fallsBackToReadyEngine"
        static let usesFormattingContext = "usesFormattingContext"
        static let allowsVoiceEditing = "allowsVoiceEditing"
        static let voiceEditShortcut = "voiceEditShortcut"
        static let contextExcludedApplications = "contextExcludedApplications"
    }
}
