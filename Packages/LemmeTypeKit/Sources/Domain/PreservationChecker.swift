import Foundation

/// What a rewrite changed that it must not (E10-S3). Raw values are stable
/// diagnostics identifiers.
public enum PreservationViolation: String, CaseIterable, Sendable {
    /// A number was dropped, changed, or added.
    case numberChanged = "number-changed"
    /// A day, month, or relative date ("tomorrow") was dropped, changed, or added.
    case dateChanged = "date-changed"
    /// A name was dropped, or a name or recipient that was not said appeared.
    case nameChanged = "name-changed"
    /// A negation ("not", "never", "n't") was dropped or added.
    case negationChanged = "negation-changed"
    /// A commitment ("will", "must", "promise", "might") was dropped, weakened, or added.
    case commitmentChanged = "commitment-changed"
    /// A link or email address was dropped or added.
    case linkChanged = "link-changed"
}

/// A deterministic check that a rewrite kept what was said (E10-S3). It
/// cannot judge meaning in general; it catches the changes that do the most
/// damage — facts, names, negation, commitments, and invented recipients —
/// and the preview shows the rest. Pure; text is compared in memory only.
public enum PreservationChecker {
    /// The ways `rewritten` differs from `original` that a rewrite must not, in a stable order.
    public static func violations(original: String, rewritten: String) -> [PreservationViolation] {
        let before = PreservationFacts(original)
        let after = PreservationFacts(rewritten)
        var found: [PreservationViolation] = []
        if before.numbers != after.numbers { found.append(.numberChanged) }
        if before.dates != after.dates { found.append(.dateChanged) }
        if !before.names.isSubset(of: after.words) || !after.names.isSubset(of: before.words) {
            found.append(.nameChanged)
        }
        if before.negations != after.negations { found.append(.negationChanged) }
        if before.commitments != after.commitments { found.append(.commitmentChanged) }
        if before.links != after.links { found.append(.linkChanged) }
        return found
    }
}

/// Everything the check compares, extracted from one text.
private struct PreservationFacts {
    var numbers: Set<String> = []
    var dates: Set<String> = []
    var names: Set<String> = []
    var words: Set<String> = []
    var negations = 0
    var commitments: Set<String> = []
    var links: Set<String> = []

    init(_ text: String) {
        let body = Self.removingListMarkers(text)
        links = Self.links(in: body)
        numbers = Self.numbers(in: Self.removingLinks(body))
        let tokens = Self.tokens(in: body)
        var sentenceStart = true
        for token in tokens {
            let lower = token.word.lowercased()
            words.insert(lower)
            if Self.relativeDates.contains(lower) || (token.isCapitalized && Self.calendarNames.contains(lower)) {
                dates.insert(lower)
            }
            if Self.numberWords.contains(lower) { numbers.insert(lower) }
            negations += Self.negationCount(lower)
            if let commitment = Self.commitment(lower) { commitments.insert(commitment) }
            if token.isCapitalized, !sentenceStart, !Self.isPronounI(lower), !Self.calendarNames.contains(lower),
                !Self.greetings.contains(lower)
            {
                names.insert(lower)
            }
            sentenceStart = token.endsSentence
        }
    }

    // MARK: Extraction

    struct Token {
        let word: String
        let isCapitalized: Bool
        let endsSentence: Bool
    }

    static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            guard isWordScalar(scalars[index]) else {
                index += 1
                continue
            }
            var end = index
            while end < scalars.count, isWordScalar(scalars[end]) || isJoiner(scalars, end) { end += 1 }
            let word = String(String.UnicodeScalarView(scalars[index..<end]))
            // Sentence ends at . ! ? or a line break before the next word.
            var lookahead = end
            var ends = false
            while lookahead < scalars.count, !isWordScalar(scalars[lookahead]) {
                if ".!?\n".unicodeScalars.contains(scalars[lookahead]) { ends = true }
                lookahead += 1
            }
            let first = word.unicodeScalars.first.map { Character($0).isUppercase } ?? false
            tokens.append(Token(word: word, isCapitalized: first, endsSentence: ends))
            index = end
        }
        return tokens
    }

    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
    }

    /// An apostrophe or hyphen between two word characters stays in the word.
    static func isJoiner(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        guard "'’-".unicodeScalars.contains(scalars[index]), index + 1 < scalars.count else { return false }
        return isWordScalar(scalars[index + 1])
    }

    static func removingListMarkers(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?m)^[ \t]*(?:[-•*]|\d+[.)])[ \t]+"#, with: "", options: .regularExpression)
    }

    static let linkPattern = #"https?://[^\s]+|www\.[^\s]+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+"#

    static func links(in text: String) -> Set<String> {
        var found: Set<String> = []
        var search = text.startIndex..<text.endIndex
        while let range = text.range(of: linkPattern, options: .regularExpression, range: search) {
            found.insert(
                text[range].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)\"'")))
            search = range.upperBound..<text.endIndex
        }
        return found
    }

    static func removingLinks(_ text: String) -> String {
        text.replacingOccurrences(of: linkPattern, with: " ", options: .regularExpression)
    }

    static func numbers(in text: String) -> Set<String> {
        var found: Set<String> = []
        var search = text.startIndex..<text.endIndex
        while let range = text.range(of: #"\d(?:[\d,.:]*\d)?"#, options: .regularExpression, range: search) {
            found.insert(String(text[range]).replacingOccurrences(of: ",", with: ""))
            search = range.upperBound..<text.endIndex
        }
        return found
    }

    // MARK: Vocabulary

    static let relativeDates: Set<String> = ["today", "tomorrow", "yesterday", "tonight"]
    /// Capitalised only; "may" and "march" are ordinary words.
    static let calendarNames: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "january", "february",
        "april", "june", "july", "august", "september", "october", "november", "december",
    ]
    static let numberWords: Set<String> = [
        "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "twenty",
        "thirty", "forty", "fifty", "hundred", "thousand", "million",
    ]
    /// Words an email greeting or sign-off adds; they are not names.
    static let greetings: Set<String> = [
        "hi", "hello", "hey", "dear", "best", "regards", "thanks", "thank", "sincerely", "cheers", "kind", "warm",
    ]

    static func isPronounI(_ lower: String) -> Bool {
        lower == "i" || lower.hasPrefix("i'") || lower.hasPrefix("i’")
    }

    static func negationCount(_ lower: String) -> Int {
        switch lower {
        case "not", "no", "never", "cannot", "nothing", "nobody", "none", "neither", "nor", "without": 1
        default: lower.hasSuffix("n't") || lower.hasSuffix("n’t") ? 1 : 0
        }
    }

    static func commitment(_ lower: String) -> String? {
        switch lower {
        case "will", "shall", "must", "might", "maybe", "perhaps", "definitely", "guarantee", "promise":
            return lower
        case "promises", "promised": return "promise"
        case "won't", "won’t": return "will"
        default:
            return lower.hasSuffix("'ll") || lower.hasSuffix("’ll") ? "will" : nil
        }
    }
}
