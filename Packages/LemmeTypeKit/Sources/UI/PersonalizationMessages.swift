import Domain
import Foundation

extension PersonalizationError {
    /// Plain-language explanation for Settings. Never repeats the rejected text.
    public var userMessage: String {
        switch self {
        case .empty(let field):
            String(localized: "\(field.displayName) can’t be empty.", bundle: .module)
        case .tooLong(let field, let limit):
            String(localized: "\(field.displayName) can be at most \(limit) characters.", bundle: .module)
        case .tooManySpellings(let limit):
            String(localized: "Add at most \(limit) “sounds like” spellings.", bundle: .module)
        case .duplicate(let field):
            String(localized: "Another item already uses this \(field.displayName.lowercased()).", bundle: .module)
        case .limitReached(let kind, let limit):
            String(localized: "You can keep up to \(limit) \(kind.pluralName).", bundle: .module)
        case .notFound:
            String(localized: "That item no longer exists.", bundle: .module)
        case .unreadable:
            String(
                localized:
                    "Your saved personalization couldn’t be read, so LemmeType started fresh. The old file was kept next to the new one.",
                bundle: .module)
        case .unsupportedVersion:
            String(
                localized:
                    "Your saved personalization was made by a newer LemmeType. It was kept, and LemmeType started fresh.",
                bundle: .module)
        case .invalidFile:
            String(localized: "This isn’t a LemmeType personalization file.", bundle: .module)
        case .storageFailure:
            String(localized: "LemmeType couldn’t save your changes to disk.", bundle: .module)
        }
    }
}

extension PersonalizationField {
    public var displayName: String {
        switch self {
        case .term: String(localized: "Word or name", bundle: .module)
        case .soundsLike: String(localized: "Sounds like", bundle: .module)
        case .spoken: String(localized: "Spoken phrase", bundle: .module)
        case .written: String(localized: "Written text", bundle: .module)
        case .trigger: String(localized: "Trigger", bundle: .module)
        case .expansion: String(localized: "Snippet text", bundle: .module)
        case .modeName: String(localized: "Mode name", bundle: .module)
        }
    }
}

extension PersonalizationKind {
    public var pluralName: String {
        switch self {
        case .vocabulary: String(localized: "vocabulary words", bundle: .module)
        case .replacement: String(localized: "replacements", bundle: .module)
        case .snippet: String(localized: "snippets", bundle: .module)
        case .mode: String(localized: "custom modes", bundle: .module)
        case .appRule: String(localized: "app rules", bundle: .module)
        }
    }
}
