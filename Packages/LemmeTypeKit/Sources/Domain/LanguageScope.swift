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
    /// English on the device, plus Telugu through Cloud speech (E13-S8): the languages the paid launch offers.
    /// No Automatic detection and no translation; English models only.
    case englishWithCloud = "english-with-cloud"
    /// Every language in ``SpokenLanguages``, with their support status shown.
    case allLanguages = "all-languages"

    /// Whether a stored language value (BCP 47 or ``SpokenLanguages/automatic``) is offered.
    public func offers(language: String) -> Bool {
        switch self {
        case .allLanguages: true
        case .englishOnly: SpokenLanguages.isEnglish(language)
        case .englishWithCloud: SpokenLanguages.isEnglish(language) || SpokenLanguages.code(of: language) == "te"
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
