import Foundation

/// Why the text offered for review is not a rewrite (E10-S3). Raw values are
/// stable diagnostics identifiers; none contains dictated text.
public enum RewriteNotice: Equatable, Sendable {
    /// The on-device model cannot run (off, not eligible, still preparing, language).
    case unavailable(RewriterAvailability)
    /// The model declined the request.
    case refused
    /// The text does not fit in the model's context.
    case tooLong
    /// The model failed or returned nothing usable.
    case failed
    /// The result changed something it must not (see ``PreservationViolation``).
    case meaningChanged([PreservationViolation])

    public var identifier: String {
        switch self {
        case .unavailable(let availability): "rewrite.\(availability.identifier)"
        case .refused: "rewrite.refused"
        case .tooLong: "rewrite.too-long"
        case .failed: "rewrite.failed"
        case .meaningChanged: "rewrite.meaning-changed"
        }
    }

    /// Trying the rewrite again unchanged can help.
    public var isRetryable: Bool {
        switch self {
        case .failed, .unavailable(.modelNotReady): true
        case .unavailable, .refused, .tooLong, .meaningChanged: false
        }
    }
}

/// A dictation waiting for the user's decision before anything is inserted
/// (E10-S4): the rewrite, the text it came from, and whether the rewrite
/// applied. In memory only; it is never logged, persisted, or put in
/// diagnostics, and it is dropped when the session ends.
public struct DictationReview: Equatable, Sendable {
    /// What Insert delivers: the rewrite, or the original when ``notice`` is set.
    public let text: String
    /// The written text before the style step.
    public let original: String
    /// BCP 47 language of ``text`` (`en` after a translation).
    public let language: String
    /// The style that was requested.
    public let style: StyleOptions
    /// Set when the rewrite did not apply; ``text`` then equals ``original``.
    public let notice: RewriteNotice?

    public init(
        text: String, original: String, language: String, style: StyleOptions, notice: RewriteNotice? = nil
    ) {
        self.text = text
        self.original = original
        self.language = language
        self.style = style
        self.notice = notice
    }

    /// Whether ``text`` is a rewrite.
    public var isRewritten: Bool { notice == nil }
}

extension DictationReview: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "DictationReview(redacted)" }
    public var debugDescription: String { description }
}
