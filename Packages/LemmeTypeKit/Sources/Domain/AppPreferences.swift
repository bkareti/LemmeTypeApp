/// Small, non-sensitive app preferences persisted between launches.
public protocol AppPreferences: AnyObject, Sendable {
    var hasCompletedOnboarding: Bool { get set }
    /// The user's dictation shortcut; `nil` means the default.
    var dictationShortcut: KeyboardShortcut? { get set }
    var activationMode: ActivationMode { get set }
    var audioInput: AudioInputSelection { get set }
    /// Start/stop sounds; off by default.
    var playsFeedbackSounds: Bool { get set }
    /// BCP 47 dictation language; English only in the MVP.
    var dictationLanguage: String { get set }
    /// Exact or Clean; stored with each session when it starts.
    var writingMode: WritingMode { get set }
    /// The user's recognition engine; `nil` means Automatic.
    var selectedEngine: RecognitionEngineID? { get set }
    /// Use another ready engine, without asking, when the selected one isn't
    /// ready. Off by default.
    var fallsBackToReadyEngine: Bool { get set }
    /// What happens when direct insertion is unsupported.
    var clipboardFallback: ClipboardFallbackPolicy { get set }
    /// Read text near the cursor to fit dictation in (E3). Off by default.
    var usesFormattingContext: Bool { get set }
    /// Allow the voice-editing shortcut to read the selection. On by default.
    var allowsVoiceEditing: Bool { get set }
    /// Bundle identifiers excluded from all context use.
    var contextExcludedApplications: [String] { get set }
}

extension AppPreferences {
    /// The engine choice to store with a new session.
    public var enginePreference: EnginePreference {
        EnginePreference(selected: selectedEngine, fallsBackAutomatically: fallsBackToReadyEngine)
    }

    /// The context rules, read for every activation.
    public var contextPolicy: ContextPolicy {
        ContextPolicy(
            usesFormattingContext: usesFormattingContext, allowsVoiceEditing: allowsVoiceEditing,
            excludedApplications: Set(contextExcludedApplications))
    }

    public static var defaultDictationLanguage: String { "en-US" }
}
