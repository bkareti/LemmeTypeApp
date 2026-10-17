/// A field of a personalization entry, for validation messages.
public enum PersonalizationField: String, Sendable, CaseIterable {
    case term
    case soundsLike = "sounds-like"
    case spoken
    case written
    case trigger
    case expansion
    /// A dictation mode's name (E4-S5).
    case modeName = "mode-name"
    /// A per-app rule's application (E4-S7).
    case application
    /// A custom mode's language code (E4-S5).
    case language
}

/// A kind of personalization item, for count limits and summaries.
public enum PersonalizationKind: String, Sendable, CaseIterable {
    case vocabulary
    case replacement
    case snippet
    case mode
    case appRule = "app-rule"
}

/// Why a personalization change or file was rejected. Never carries the text
/// that was rejected (ADR 0020).
public enum PersonalizationError: LemmeTypeError, Equatable {
    case empty(PersonalizationField)
    case tooLong(PersonalizationField, limit: Int)
    /// More "sounds like" spellings than ``PersonalizationLimits/soundsLikePerTerm``.
    case tooManySpellings(limit: Int)
    /// Another item already uses the same term, phrase, trigger, or name.
    case duplicate(PersonalizationField)
    case limitReached(PersonalizationKind, limit: Int)
    /// The item to change or remove no longer exists.
    case notFound
    /// The stored library could not be read; it was moved aside, not overwritten.
    case unreadable
    /// A file (store or import) was written by a newer LemmeType.
    case unsupportedVersion
    /// An import file is not a LemmeType personalization file.
    case invalidFile
    case storageFailure

    public var identifier: String {
        switch self {
        case .empty(let field): "personalization.empty-\(field.rawValue)"
        case .tooLong(let field, _): "personalization.too-long-\(field.rawValue)"
        case .tooManySpellings: "personalization.too-many-spellings"
        case .duplicate(let field): "personalization.duplicate-\(field.rawValue)"
        case .limitReached(let kind, _): "personalization.limit-\(kind.rawValue)"
        case .notFound: "personalization.not-found"
        case .unreadable: "personalization.unreadable"
        case .unsupportedVersion: "personalization.unsupported-version"
        case .invalidFile: "personalization.invalid-file"
        case .storageFailure: "personalization.storage-failure"
        }
    }
}
