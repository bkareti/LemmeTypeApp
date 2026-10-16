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
}

extension AppPreferences {
    public static var defaultDictationLanguage: String { "en-US" }
}
