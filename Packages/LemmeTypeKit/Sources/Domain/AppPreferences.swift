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
}

extension AppPreferences {
    /// The engine choice to store with a new session.
    public var enginePreference: EnginePreference {
        EnginePreference(selected: selectedEngine, fallsBackAutomatically: fallsBackToReadyEngine)
    }

    public static var defaultDictationLanguage: String { "en-US" }
}
