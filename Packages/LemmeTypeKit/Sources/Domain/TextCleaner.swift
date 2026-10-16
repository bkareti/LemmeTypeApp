/// One deterministic cleanup rule. Raw values are stable identifiers for
/// settings and tests.
public enum CleanupRule: String, CaseIterable, Codable, Sendable {
    /// "comma", "question mark", "new line", … become punctuation.
    case spokenPunctuation = "spoken-punctuation"
    /// "Tuesday—sorry—Wednesday" becomes "Wednesday" when both words are the
    /// same kind (weekdays, months, numbers); anything else is left alone.
    case selfCorrection = "self-correction"
    /// Standalone hesitation sounds: um, uh, er, erm, ah, hmm.
    case fillerWords = "filler-words"
    /// An immediately repeated word ("the the"), except legitimate doubles.
    case repeatedWords = "repeated-words"
    /// Sentence starts and the pronoun "I".
    case capitalization
    /// A final period when the text has no terminal punctuation.
    case terminalPunctuation = "terminal-punctuation"
}

/// Which Clean Writing rules run. Codable so a later settings screen can store it.
public struct CleanupConfiguration: Equatable, Codable, Sendable {
    public var enabledRules: Set<CleanupRule>

    public init(enabledRules: Set<CleanupRule> = Set(CleanupRule.allCases)) {
        self.enabledRules = enabledRules
    }

    public static let `default` = CleanupConfiguration()

    public func isEnabled(_ rule: CleanupRule) -> Bool { enabledRules.contains(rule) }
}

/// A single change made by a rule. In memory only (it contains dictated text).
public struct CleanupTransformation: Equatable, Sendable {
    public let rule: CleanupRule
    public let before: String
    public let after: String

    public init(rule: CleanupRule, before: String, after: String) {
        self.rule = rule
        self.before = before
        self.after = after
    }
}

public struct CleanupResult: Equatable, Sendable {
    public let text: String
    public let transformations: [CleanupTransformation]
}

/// Exact Dictation and deterministic Clean Writing (E2-S6,
/// docs/decisions/0014-writing-modes.md).
///
/// - Exact only normalises whitespace (trims, collapses runs, keeps line breaks).
/// - Clean runs the enabled rules in a fixed order over word tokens. Tokens
///   that look like numbers, URLs, email addresses, identifiers, or that sit
///   inside quotes are protected: no rule rewrites them, except
///   self-correction, which may replace one number with another and is tested
///   for it.
public struct TextCleaner: Sendable {
    public let configuration: CleanupConfiguration

    public init(configuration: CleanupConfiguration = .default) {
        self.configuration = configuration
    }

    /// Adapter for `TranscriptionPipeline(write:)`.
    public static let write: @Sendable (String, WritingMode) -> String = { text, mode in
        TextCleaner().apply(text, mode: mode).text
    }

    public func apply(_ text: String, mode: WritingMode) -> CleanupResult {
        switch mode {
        case .exact:
            return CleanupResult(text: Self.normalizeWhitespace(text), transformations: [])
        case .clean:
            var document = CleanupDocument(Self.normalizeWhitespace(text))
            let rules: [(CleanupRule, (inout CleanupDocument) -> Void)] = [
                (.spokenPunctuation, CleanupRules.spokenPunctuation),
                (.selfCorrection, CleanupRules.selfCorrection),
                (.fillerWords, CleanupRules.fillerWords),
                (.repeatedWords, CleanupRules.repeatedWords),
                (.capitalization, CleanupRules.capitalization),
                (.terminalPunctuation, CleanupRules.terminalPunctuation),
            ]
            for (rule, run) in rules where configuration.isEnabled(rule) {
                document.currentRule = rule
                run(&document)
            }
            return CleanupResult(text: document.text, transformations: document.transformations)
        }
    }

    /// Trims, collapses spaces and tabs, and keeps at most one blank line.
    public static func normalizeWhitespace(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" }).joined(separator: " ")
        }
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) {
            result.append(line)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }
}
