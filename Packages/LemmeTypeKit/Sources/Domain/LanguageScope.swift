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
    /// Every language in ``SpokenLanguages``, with their support status shown.
    case allLanguages = "all-languages"

    /// Whether a stored language value (BCP 47 or ``SpokenLanguages/automatic``) is offered.
    public func offers(language: String) -> Bool {
        switch self {
        case .allLanguages: true
        case .englishOnly: SpokenLanguages.isEnglish(language)
        }
    }

    /// The "Text you get" choices. English-only has nothing to translate, so
    /// only the original words.
    public var speechOutputs: [SpeechOutput] {
        switch self {
        case .allLanguages: SpeechOutput.allCases
        case .englishOnly: [.original]
        }
    }

    /// Whether a downloadable model is listed. English-only lists only models
    /// whose every language is English, so testers are never offered a larger
    /// multilingual download they cannot use.
    public func lists(_ asset: ModelAsset) -> Bool {
        switch self {
        case .allLanguages: true
        case .englishOnly: !asset.languages.isEmpty && asset.languages.allSatisfy(SpokenLanguages.isEnglish)
        }
    }
}
