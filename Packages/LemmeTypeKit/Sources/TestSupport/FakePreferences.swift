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
    }

    private let values: Mutex<Values>

    public init(
        hasCompletedOnboarding: Bool = false,
        dictationShortcut: KeyboardShortcut? = nil,
        activationMode: ActivationMode = .pushToTalk,
        audioInput: AudioInputSelection = .systemDefault,
        playsFeedbackSounds: Bool = false,
        dictationLanguage: String = "en-US"
    ) {
        values = Mutex(
            Values(
                hasCompletedOnboarding: hasCompletedOnboarding,
                dictationShortcut: dictationShortcut,
                activationMode: activationMode,
                audioInput: audioInput,
                playsFeedbackSounds: playsFeedbackSounds,
                dictationLanguage: dictationLanguage
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
}
