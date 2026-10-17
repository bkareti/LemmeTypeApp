import Domain
import Synchronization

/// In-memory `AppPreferences`.
public final class FakePreferences: AppPreferences {
    private struct Values {
        var hasCompletedOnboarding: Bool
        var dictationShortcut: KeyboardShortcut?
        var activationMode: ActivationMode
        var audioInput: AudioInputSelection
        var playsFeedbackSounds: Bool
        var dictationLanguage: String
        var writingMode: WritingMode
        var selectedEngine: RecognitionEngineID?
        var clipboardFallback: ClipboardFallbackPolicy
        var fallsBackToReadyEngine: Bool
    }

    private let values: Mutex<Values>

    public init(
        hasCompletedOnboarding: Bool = false,
        dictationShortcut: KeyboardShortcut? = nil,
        activationMode: ActivationMode = .pushToTalk,
        audioInput: AudioInputSelection = .systemDefault,
        playsFeedbackSounds: Bool = false,
        dictationLanguage: String = "en-US",
        writingMode: WritingMode = .exact,
        selectedEngine: RecognitionEngineID? = nil,
        clipboardFallback: ClipboardFallbackPolicy = .default,
        fallsBackToReadyEngine: Bool = false
    ) {
        values = Mutex(
            Values(
                hasCompletedOnboarding: hasCompletedOnboarding,
                dictationShortcut: dictationShortcut,
                activationMode: activationMode,
                audioInput: audioInput,
                playsFeedbackSounds: playsFeedbackSounds,
                dictationLanguage: dictationLanguage,
                writingMode: writingMode,
                selectedEngine: selectedEngine,
                clipboardFallback: clipboardFallback,
                fallsBackToReadyEngine: fallsBackToReadyEngine
            ))
    }

    public var hasCompletedOnboarding: Bool {
        get { values.withLock { $0.hasCompletedOnboarding } }
        set { values.withLock { $0.hasCompletedOnboarding = newValue } }
    }

    public var dictationShortcut: KeyboardShortcut? {
        get { values.withLock { $0.dictationShortcut } }
        set { values.withLock { $0.dictationShortcut = newValue } }
    }

    public var activationMode: ActivationMode {
        get { values.withLock { $0.activationMode } }
        set { values.withLock { $0.activationMode = newValue } }
    }

    public var audioInput: AudioInputSelection {
        get { values.withLock { $0.audioInput } }
        set { values.withLock { $0.audioInput = newValue } }
    }

    public var playsFeedbackSounds: Bool {
        get { values.withLock { $0.playsFeedbackSounds } }
        set { values.withLock { $0.playsFeedbackSounds = newValue } }
    }

    public var dictationLanguage: String {
        get { values.withLock { $0.dictationLanguage } }
        set { values.withLock { $0.dictationLanguage = newValue } }
    }

    public var writingMode: WritingMode {
        get { values.withLock { $0.writingMode } }
        set { values.withLock { $0.writingMode = newValue } }
    }

    public var selectedEngine: RecognitionEngineID? {
        get { values.withLock { $0.selectedEngine } }
        set { values.withLock { $0.selectedEngine = newValue } }
    }

    public var clipboardFallback: ClipboardFallbackPolicy {
        get { values.withLock { $0.clipboardFallback } }
        set { values.withLock { $0.clipboardFallback = newValue } }
    }

    public var fallsBackToReadyEngine: Bool {
        get { values.withLock { $0.fallsBackToReadyEngine } }
        set { values.withLock { $0.fallsBackToReadyEngine = newValue } }
    }
}
