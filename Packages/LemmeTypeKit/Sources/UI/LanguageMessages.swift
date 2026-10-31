import Domain
import Foundation

/// User-facing words for languages, output, and readiness (E9-S3). Never
/// includes spoken or dictated text.
extension SpokenLanguage {
    /// "Hindi · हिन्दी" (English shows once).
    var displayName: String {
        englishName == nativeName ? englishName : "\(englishName) · \(nativeName)"
    }
}

extension LanguageSupportStatus {
    /// Shown next to languages that are not yet validated.
    var badge: String? {
        switch self {
        case .validated: nil
        case .evaluation: String(localized: "Evaluation", bundle: .module)
        }
    }
}

extension SpeechOutput {
    var displayName: String {
        switch self {
        case .original: String(localized: "Original language", bundle: .module)
        case .english: String(localized: "English", bundle: .module)
        }
    }

    var summary: String {
        switch self {
        case .original:
            String(localized: "Types what you said, in the language you said it. Nothing is translated.", bundle: .module)
        case .english:
            String(
                localized:
                    "Turns speech in another language into English on this Mac. You read the translation before anything is inserted.",
                bundle: .module)
        }
    }
}

extension LanguageReadiness {
    /// One sentence for Settings, the menu, and the overlay.
    var userMessage: String {
        switch self {
        case .ready(let engine):
            String(localized: "Ready · \(engine.displayName) on this Mac", bundle: .module)
        case .needsModel(let id):
            if let model = ModelCatalog.asset(id) {
                String(
                    localized:
                        "Needs the \(model.displayName) model (\(model.downloadBytes.formatted(.byteCount(style: .file)))). Download it in Settings › Dictation › Models.",
                    bundle: .module)
            } else {
                String(localized: "Needs a model download in Settings › Dictation › Models.", bundle: .module)
            }
        case .unsupportedOnThisMac(.insufficientMemory):
            String(localized: "This Mac doesn’t have enough memory for the model this needs.", bundle: .module)
        case .unsupportedOnThisMac(.hardware):
            String(localized: "This needs a Mac with Apple silicon.", bundle: .module)
        case .unsupportedOnThisMac:
            String(localized: "This isn’t available on this Mac.", bundle: .module)
        case .noEngine:
            String(
                localized: "No on-device engine can do this. Choose another language or output.", bundle: .module)
        case .engineNotReady:
            String(
                localized: "The selected engine isn’t ready for this. Choose another in Settings › Dictation.",
                bundle: .module)
        }
    }
}

extension DictationSettingsModel {
    nonisolated static func settingLanguageName(_ identifier: String) -> String {
        if SpokenLanguages.isAutomatic(identifier) { return String(localized: "Automatic", bundle: .module) }
        if let language = SpokenLanguages.language(for: identifier), !SpokenLanguages.isEnglish(identifier) {
            return language.displayName
        }
        return languageName(identifier)
    }
}
