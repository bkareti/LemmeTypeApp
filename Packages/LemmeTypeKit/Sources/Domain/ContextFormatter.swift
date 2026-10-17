/// One context-aware formatting rule (E3-S3). Raw values are stable identifiers.
public enum ContextRule: String, CaseIterable, Sendable {
    /// A space between the preceding text and the dictation.
    case leadingSpace = "leading-space"
    /// A space between the dictation and the following word.
    case trailingSpace = "trailing-space"
    /// Clean: a capitalized common first word becomes lowercase mid-sentence.
    case continuationCase = "continuation-case"
    /// Clean: a final period is dropped when the sentence continues after the caret.
    case midSentencePeriod = "mid-sentence-period"
    /// Clean: punctuation already next to the caret is not repeated.
    case duplicatePunctuation = "duplicate-punctuation"
}

/// A single change made by a ``ContextRule``. In memory only.
public struct ContextTransformation: Equatable, Sendable {
    public let rule: ContextRule
    public let before: String
    public let after: String
}

public struct ContextFormatting: Equatable, Sendable {
    public let text: String
    public let transformations: [ContextTransformation]
}

/// Fits written text into the text around the caret, deterministically and
/// without a language model (E3-S3, docs/decisions/0017-cursor-context.md).
///
/// Runs after the writing mode. Exact Dictation only gets separating spaces;
/// Clean Writing also gets the case and punctuation rules. Only words in
/// ``commonWords`` are ever lower-cased, so names ("Paris", "Monday"),
/// acronyms, identifiers, and "I" keep their case.
public enum ContextFormatter {
    /// Adapter for `TranscriptionPipeline(format:)`.
    public static let format: @Sendable (String, WritingMode, CursorContext) -> String = { text, mode, context in
        apply(text, mode: mode, context: context).text
    }

    public static func apply(_ text: String, mode: WritingMode, context: CursorContext) -> ContextFormatting {
        var result = Formatting(text: text)
        guard !text.isEmpty else { return result.finished }
        let preceding = context.precedingText
        let following = context.followingText
        if mode == .clean {
            removeDuplicatePunctuation(&result, preceding: preceding, following: following)
            removeMidSentencePeriod(&result, following: following)
            lowercaseContinuation(&result, preceding: preceding)
        }
        addLeadingSpace(&result, preceding: preceding)
        addTrailingSpace(&result, following: following)
        return result.finished
    }

    // MARK: Rules

    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "”", "’", "'", ")", "]", "}"]
    private static let openers: Set<Character> = ["(", "[", "{", "“", "‘", "/", "@", "#", "-", "_"]
    private static let joinablePunctuation: Set<Character> = [".", ",", ";", ":", "!", "?"]

    private static func removeDuplicatePunctuation(_ result: inout Formatting, preceding: String, following: String) {
        if let first = result.text.first, joinablePunctuation.contains(first),
            trimmingSpaces(preceding).last == first
        {
            result.change(.duplicatePunctuation, String(first), "") {
                String($0.dropFirst()).trimmingLeadingSpaces()
            }
        }
        if let last = result.text.last, joinablePunctuation.contains(last), following.first == last {
            result.change(.duplicatePunctuation, String(last), "") { String($0.dropLast()) }
        }
    }

    /// "hello." before "world" → "hello"; never "..." and never before a capital.
    private static func removeMidSentencePeriod(_ result: inout Formatting, following: String) {
        guard result.text.hasSuffix("."), !result.text.hasSuffix(".."), continuesSentence(following) else { return }
        result.change(.midSentencePeriod, ".", "") { String($0.dropLast()) }
    }

    private static func lowercaseContinuation(_ result: inout Formatting, preceding: String) {
        guard !isSentenceStart(preceding) else { return }
        let word = String(result.text.prefix { $0.isLetter || $0 == "'" || $0 == "’" })
        guard let first = word.first, first.isUppercase, word.dropFirst().allSatisfy({ !$0.isUppercase }),
            commonWords.contains(word.lowercased().replacingOccurrences(of: "’", with: "'"))
        else { return }
        let lowered = first.lowercased() + word.dropFirst()
        result.change(.continuationCase, word, lowered) { lowered + $0.dropFirst(word.count) }
    }

    private static func addLeadingSpace(_ result: inout Formatting, preceding: String) {
        guard let previous = preceding.last, !previous.isWhitespace, !openers.contains(previous),
            !isOpeningQuote(at: preceding), let first = result.text.first,
            first.isLetter || first.isNumber || first == "“" || first == "(" || first == "\""
        else { return }
        result.change(.leadingSpace, "", " ") { " " + $0 }
    }

    private static func addTrailingSpace(_ result: inout Formatting, following: String) {
        guard let next = following.first, next.isLetter || next.isNumber || next == "(" || next == "“",
            let last = result.text.last, !last.isWhitespace, !openers.contains(last)
        else { return }
        result.change(.trailingSpace, "", " ") { $0 + " " }
    }

    // MARK: Helpers

    /// At the start of the field, after a new line, or after ".", "!", "?"
    /// (optionally followed by closing quotes or brackets).
    static func isSentenceStart(_ preceding: String) -> Bool {
        var trimmed = Substring(trimmingSpaces(preceding))
        guard let last = trimmed.last else { return true }
        if last.isNewline { return true }
        while let tail = trimmed.last, closers.contains(tail) { trimmed = trimmed.dropLast() }
        return trimmed.last.map(sentenceEnders.contains) ?? true
    }

    /// The following text, on the same line, starts with a lowercase word or a number.
    private static func continuesSentence(_ following: String) -> Bool {
        guard let next = following.first(where: { $0 != " " && $0 != "\t" }), !next.isNewline else { return false }
        return next.isLowercase || next.isNumber
    }

    /// A straight double quote with an odd count before it opens a quotation.
    private static func isOpeningQuote(at preceding: String) -> Bool {
        preceding.last == "\"" && preceding.filter { $0 == "\"" }.count % 2 == 1
    }

    /// Removes trailing spaces and tabs (not new lines).
    private static func trimmingSpaces(_ text: String) -> String {
        var text = text
        while let last = text.last, last == " " || last == "\t" { text.removeLast() }
        return text
    }

    /// Common words that start a clause and are not names. Version-controlled;
    /// a word outside this list keeps its case.
    static let commonWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "so", "then", "also", "because", "if", "when", "while", "after",
        "before", "since", "although", "though", "however", "therefore", "yet", "nor", "for", "with", "without",
        "to", "of", "in", "on", "at", "by", "from", "as", "about", "into", "over", "under", "it", "its", "this",
        "that", "these", "those", "there", "here", "we", "you", "he", "she", "they", "me", "us", "him", "her",
        "them", "my", "our", "your", "his", "their", "what", "which", "who", "whom", "whose", "where", "why", "how",
        "is", "are", "was", "were", "be", "been", "am", "do", "does", "did", "have", "has", "had", "would", "can",
        "could", "should", "might", "must", "not", "no", "yes", "maybe", "just", "only", "even", "still", "really",
        "very", "please", "thanks", "thank", "let", "all", "some", "any", "every", "each", "more", "most", "many",
        "much", "few", "other", "another", "such", "both", "either", "neither", "now", "today", "tomorrow",
        "yesterday", "again", "too", "well", "oh", "okay", "ok", "hello", "hi", "hey", "sure", "actually",
        "basically", "probably", "definitely", "perhaps", "especially", "instead", "otherwise", "meanwhile",
        "finally", "first", "next", "hopefully", "unfortunately", "luckily", "anyway", "like", "it's", "that's",
        "there's", "let's", "we're", "you're", "they're", "don't", "doesn't", "didn't", "can't", "won't", "isn't",
        "wasn't", "we'll", "you'll", "we've", "you've",
    ]
}

/// Text being formatted plus the log of changes.
private struct Formatting {
    var text: String
    var transformations: [ContextTransformation] = []

    mutating func change(_ rule: ContextRule, _ before: String, _ after: String, _ apply: (String) -> String) {
        text = apply(text)
        transformations.append(ContextTransformation(rule: rule, before: before, after: after))
    }

    var finished: ContextFormatting { ContextFormatting(text: text, transformations: transformations) }
}

extension String {
    fileprivate func trimmingLeadingSpaces() -> String {
        String(drop { $0 == " " || $0 == "\t" })
    }
}
