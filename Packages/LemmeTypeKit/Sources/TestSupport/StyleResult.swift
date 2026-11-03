import Domain
import Foundation

/// What a tone, format, and length rewrite did with a dictation (E10). Only
/// what can be checked without a person: whether it applied, why not, whether
/// it kept the facts, and whether the format and length were followed. Tone
/// ("professional", "friendly") cannot be checked by rule and is left to the
/// human review in `docs/testing/style-rewriting.md`.
public struct StyleResult: Codable, Equatable, Sendable {
    /// The result of one rule check; `notChecked` where no rule applies.
    public enum Check: String, Codable, Equatable, Sendable {
        case followed
        case notFollowed = "not-followed"
        case notChecked = "not-checked"

        init(_ followed: Bool) { self = followed ? .followed : .notFollowed }
    }

    /// `StyleOptions.identifier`, such as `professional-email-concise`.
    public let style: String
    /// The rewrite reached the review; otherwise the original was offered with a notice.
    public let applied: Bool
    /// `RewriteNotice.identifier` when it did not apply.
    public let notice: String?
    /// `PreservationViolation` raw values between the original and the rewrite.
    public let violations: [String]
    /// Not checked when the format has no rule-checkable shape (message, email) or nothing applied.
    public let format: Check
    /// Not checked unless the length preference is concise and the rewrite applied.
    public let length: Check
    public let originalWords: Int
    public let rewrittenWords: Int

    public init(
        style: String, applied: Bool, notice: String?, violations: [String], format: Check, length: Check,
        originalWords: Int, rewrittenWords: Int
    ) {
        self.style = style
        self.applied = applied
        self.notice = notice
        self.violations = violations
        self.format = format
        self.length = length
        self.originalWords = originalWords
        self.rewrittenWords = rewrittenWords
    }

    public static func of(_ review: DictationReview) -> StyleResult {
        let original = TranscriptNormalizer.words(review.original).count
        let rewritten = TranscriptNormalizer.words(review.text).count
        let applied = review.notice == nil
        return StyleResult(
            style: review.style.identifier, applied: applied, notice: review.notice?.identifier,
            violations: PreservationChecker.violations(original: review.original, rewritten: review.text).map(
                \.rawValue),
            format: applied ? formatCheck(review.style.format, text: review.text) : .notChecked,
            length: applied && review.style.length == .concise
                ? Check(original <= 5 ? rewritten <= original : rewritten < original) : .notChecked,
            originalWords: original, rewrittenWords: rewritten)
    }

    static let listMarker = #"^[ \t]*(?:[-•*]|\d+[.)])[ \t]+"#

    static func formatCheck(_ format: WritingFormat, text: String) -> Check {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let marked = lines.filter { $0.range(of: listMarker, options: .regularExpression) != nil }
        switch format {
        case .bulletList: return Check(!lines.isEmpty && marked.count == lines.count)
        case .plainText: return Check(marked.isEmpty)
        case .message, .email: return .notChecked
        }
    }
}
