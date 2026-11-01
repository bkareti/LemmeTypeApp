import Foundation

extension RecognitionTask {
    /// The task a language and output call for: English output translates
    /// every language except English; Automatic may be either, so it asks the
    /// engine to translate (a no-op for English speech).
    public static func required(for language: String, output: SpeechOutput) -> RecognitionTask {
        output == .english && !SpokenLanguages.isEnglish(language) ? .translateToEnglish : .transcribe
    }
}

/// Whether the chosen language and output can run right now, and what is
/// missing if not (E9-S3). Pure data: the UI words it, the recorder uses it to
/// refuse before the microphone starts.
public enum LanguageReadiness: Equatable, Sendable {
    /// `engine` will recognise it.
    case ready(engine: RecognitionEngineID)
    /// An engine could, but a model has to be downloaded first.
    case needsModel(ModelAssetID)
    /// This Mac cannot run any model for it.
    case unsupportedOnThisMac(UnsupportedReason)
    /// No engine offers the language or task (for example an unknown language).
    case noEngine
    /// The chosen engine exists but is not ready (permission, failure).
    case engineNotReady(EngineAvailability)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Stable lowercase name for diagnostics.
    public var identifier: String {
        switch self {
        case .ready: "ready"
        case .needsModel: "needs-model"
        case .unsupportedOnThisMac(let reason): "unsupported.\(reason.rawValue)"
        case .noEngine: "no-engine"
        case .engineNotReady(let availability): "engine.\(availability.identifier)"
        }
    }

    /// Whether the combination uses anything beyond English dictation. Plain
    /// English keeps its existing behaviour, including starting to record
    /// when an engine is not ready so that speech is never lost.
    public static func isBeyondEnglishDictation(language: String, output: SpeechOutput) -> Bool {
        SpokenLanguages.isAutomatic(language) || !SpokenLanguages.isEnglish(language) || output == .english
    }

    /// Checks `language` and `output` against the engines. Never prompts or downloads.
    public static func evaluate(
        language: String,
        output: SpeechOutput,
        engines: [any SpeechRecognitionEngine],
        preference: EnginePreference = .automatic,
        hardware: HardwareProfile = .current
    ) async -> LanguageReadiness {
        let need = RecognitionNeed(language: language, task: .required(for: language, output: output))
        let capable = engines.filter { $0.descriptor.supports(need) }
        guard !capable.isEmpty else { return .noEngine }
        var candidates: [(id: RecognitionEngineID, availability: EngineAvailability)] = []
        for engine in capable {
            candidates.append((engine.descriptor.id, await engine.availability(for: need)))
        }
        switch EngineSelector.choose(
            preferred: preference.selected, fallsBackAutomatically: preference.fallsBackAutomatically,
            candidates: candidates)
        {
        case .engine(let id):
            return .ready(engine: id)
        case .unavailable(_, let availability, _):
            return blocked(by: availability, need: need, hardware: hardware)
        case .noneAvailable:
            // Every capable engine is unavailable: report the most helpful reason.
            if let missing = candidates.first(where: { $0.availability == .assetsMissing }) {
                return blocked(by: missing.availability, need: need, hardware: hardware)
            }
            return blocked(by: candidates.first?.availability ?? .assetsMissing, need: need, hardware: hardware)
        }
    }

    private static func blocked(by availability: EngineAvailability, need: RecognitionNeed, hardware: HardwareProfile)
        -> LanguageReadiness
    {
        switch availability {
        case .assetsMissing:
            if let model = ModelCatalog.recommendedModel(for: need, hardware: hardware) {
                return .needsModel(model.id)
            }
            // No model that serves this request runs on this Mac: say why.
            let reason = ModelCatalog.whisperModels
                .filter { $0.serves(language: need.language, task: need.task) }
                .compactMap { $0.hardware.unsupportedReason(for: hardware) }.first
            return .unsupportedOnThisMac(reason ?? .hardware)
        case .unsupported(let reason):
            return .unsupportedOnThisMac(reason)
        case .ready:
            return .noEngine
        default:
            return .engineNotReady(availability)
        }
    }
}

extension ModelCatalog {
    /// The model to suggest downloading for `need`: the one in the tier the
    /// support matrix recommends, if this Mac can run it, otherwise the
    /// largest Whisper model it can run that serves the request. English-only
    /// models are preferred for English because they are smaller.
    public static func recommendedModel(for need: RecognitionNeed, hardware: HardwareProfile) -> ModelAsset? {
        let serving = whisperModels.filter {
            $0.serves(language: need.language, task: need.task) && $0.hardware.fit(for: hardware).canRun
        }
        guard !serving.isEmpty else { return nil }
        let wanted =
            LanguageSupportMatrix.row(language: need.language, task: need.task)?.recommendedTier ?? .balanced
        let preferred = serving.filter { $0.tier == wanted }
        // English-only models are listed first, so `first` prefers them.
        return preferred.first ?? serving.last
    }
}
