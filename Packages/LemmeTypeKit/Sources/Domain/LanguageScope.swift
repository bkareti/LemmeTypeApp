import Foundation

/// Which spoken languages a build offers (ADR 0029).
///
/// The engines, models, and pipeline keep every language in
/// ``SpokenLanguages``; the scope only decides what Settings, the menu, and
/// mode editors offer, and which models are listed for download. That keeps a
/// release honest about what was validated (the friends beta is English only)
/// without removing the multilingual code that a later language pack turns
/// back on by widening the scope.
public enum LanguageScope: String, CaseIterable, Sendable {
    /// English only: no Automatic detection, no translation, English-only models.
    case englishOnly = "english-only"
    /// English on the device, plus the Indian languages Cloud speech may serve (E13-S8, E12-S7). Which of those
    /// the user sees is decided by the Cloud engine, which offers only what the gateway lists.
    /// No Automatic detection and no translation; English models only.
    case englishWithCloud = "english-with-cloud"
    /// Every language in ``SpokenLanguages``, with their support status shown.
    case allLanguages = "all-languages"

    /// Whether a stored language value (BCP 47 or ``SpokenLanguages/automatic``) is offered.
    public func offers(language: String) -> Bool {
        switch self {
        case .allLanguages: true
        case .englishOnly: SpokenLanguages.isEnglish(language)
        case .englishWithCloud: SpokenLanguages.isEnglish(language) || SpokenLanguages.isCloudCandidate(language)
        }
    }

    /// Whether `language` is offered on an engine at `location`. The Cloud scope lists English models only, so
    /// another language can run only in the cloud: a local engine that merely names it is never offered for it.
    public func offers(language: String, at location: ProcessingLocation) -> Bool {
        guard offers(language: language) else { return false }
        switch self {
        case .allLanguages, .englishOnly: return true
        case .englishWithCloud: return SpokenLanguages.isEnglish(language) || location == .cloud
        }
    }

    /// The "Text you get" choices. English-only has nothing to translate, so
    /// only the original words.
    public var speechOutputs: [SpeechOutput] {
        switch self {
        case .allLanguages: SpeechOutput.allCases
        case .englishOnly, .englishWithCloud: [.original]
        }
    }

    /// Whether a downloadable model is listed. English-only lists only models
    /// whose every language is English, so testers are never offered a larger
    /// multilingual download they cannot use.
    public func lists(_ asset: ModelAsset) -> Bool {
        switch self {
        case .allLanguages: true
        case .englishOnly, .englishWithCloud:
            !asset.languages.isEmpty && asset.languages.allSatisfy(SpokenLanguages.isEnglish)
        }
    }
}
