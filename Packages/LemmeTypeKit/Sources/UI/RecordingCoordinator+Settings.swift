import Domain

/// What a session takes from Settings when its recording starts (E2-S9,
/// E4-S5, E4-S7): the resolved mode and everything it decides. Later changes
/// in Settings only affect the next session.
struct SessionSettings: Sendable {
    let resolved: ResolvedMode
    let language: String
    let enginePreference: EnginePreference
    let personalization: PersonalizationLibrary

    init(preferences: any AppPreferences, library: PersonalizationLibrary, target: ActivationTarget?) {
        resolved = ModeResolver.resolve(
            bundleIdentifier: target?.bundleIdentifier, defaultMode: preferences.dictationMode, library: library)
        language = resolved.mode.language ?? preferences.dictationLanguage
        enginePreference = EnginePreference(
            selected: resolved.mode.engine ?? preferences.selectedEngine,
            fallsBackAutomatically: preferences.fallsBackToReadyEngine)
        personalization = library
    }

    func session(audio: RecordedAudio, target: ActivationTarget?, purpose: SessionPurpose) -> DictationSession {
        DictationSession(
            audio: audio, target: target, mode: resolved.mode.writingMode, dictationMode: resolved.mode,
            modeSource: resolved.source, purpose: purpose, language: language, enginePreference: enginePreference,
            personalization: personalization)
    }
}

extension RecordingCoordinator {
    /// The writing mode captured when the current recording started; shown
    /// in the overlay and stored with the session.
    public var activeMode: WritingMode? { activeSettings?.resolved.mode.writingMode }

    /// The dictation mode resolved when the current recording started.
    public var activeDictationMode: DictationMode? { activeSettings?.resolved.mode }

    /// Whether the current mode came from the default or an app rule.
    public var activeModeSource: ModeSource? { activeSettings?.resolved.source }
}
