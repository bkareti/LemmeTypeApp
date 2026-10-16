/// Why a token is off limits to cleanup rules.
enum CleanupProtection: Equatable {
    /// Inside quotes, or a line break the rules must keep.
    case verbatim
    /// Contains a digit: amounts, phone numbers, versions.
    case number
    /// URLs, email addresses, dotted names, and paths.
    case address
    /// Code identifiers (camelCase, snake_case) and backtick code.
    case identifier
}

/// A word token with its surrounding punctuation split off, so rules can
/// reason about the word alone.
struct CleanupToken: Equatable {
    var leading: String
    var word: String
    var trailing: String
    var protection: CleanupProtection?

    var isProtected: Bool { protection != nil }
    /// A line break token ("\n" or "\n\n").
    var isBreak: Bool { word.allSatisfy { $0 == "\n" } && !word.isEmpty }

    var text: String { leading + word + trailing }
    var lowercasedWord: String { word.lowercased() }
}

/// Tokens being cleaned plus a log of every change.
struct CleanupDocument {
    var tokens: [CleanupToken]
    var transformations: [CleanupTransformation] = []
    var currentRule: CleanupRule = .capitalization

    init(_ text: String) {
        tokens = Self.tokenize(text)
    }

    var text: String {
        var output = ""
        for token in tokens {
            if token.isBreak {
                while output.hasSuffix(" ") { output.removeLast() }
                output += token.word
            } else {
                if !output.isEmpty && !output.hasSuffix("\n") { output += " " }
                output += token.text
            }
        }
        return output
    }

    mutating func record(_ before: String, _ after: String) {
        transformations.append(CleanupTransformation(rule: currentRule, before: before, after: after))
    }

    // MARK: Tokenizing

    static let openingPunctuation: Set<Character> = ["\"", "“", "‘", "(", "[", "'"]
    static let closingPunctuation: Set<Character> = [
        ".", ",", "!", "?", ";", ":", "\"", "”", "’", ")", "]", "…", "'",
    ]

    static func tokenize(_ text: String) -> [CleanupToken] {
        // Dashes used as separators ("Tuesday—sorry—Wednesday") become their own tokens.
        let spaced = text.replacingOccurrences(of: "—", with: " — ").replacingOccurrences(of: "–", with: " – ")
        var tokens: [CleanupToken] = []
        var inQuote = false
        for line in spaced.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.offset > 0 {
                if let last = tokens.last, last.isBreak {
                    tokens[tokens.count - 1].word = "\n\n"
                } else {
                    tokens.append(CleanupToken(leading: "", word: "\n", trailing: "", protection: .verbatim))
                }
            }
            for raw in line.element.split(separator: " ") {
                var token = split(String(raw))
                let opens = token.leading.contains { $0 == "\"" || $0 == "“" }
                let closes = token.trailing.contains { $0 == "\"" || $0 == "”" }
                if opens { inQuote = true }
                token.protection = inQuote ? .verbatim : protection(of: token.word)
                if closes { inQuote = false }
                tokens.append(token)
            }
        }
        return tokens
    }

    static func split(_ raw: String) -> CleanupToken {
        var characters = Array(raw)
        var leading = ""
        var trailing = ""
        while let first = characters.first, openingPunctuation.contains(first), characters.count > 1 {
            leading.append(first)
            characters.removeFirst()
        }
        while let last = characters.last, closingPunctuation.contains(last), characters.count > 1 {
            trailing.insert(last, at: trailing.startIndex)
            characters.removeLast()
        }
        return CleanupToken(leading: leading, word: String(characters), trailing: trailing)
    }

    /// Numbers, URLs, emails, and code-like identifiers are never rewritten.
    static func protection(of word: String) -> CleanupProtection? {
        let lower = word.lowercased()
        if word.contains(where: \.isNumber) { return .number }
        if word.contains("@") || lower.contains("://") || lower.hasPrefix("www.") { return .address }
        if word.contains("/") || word.contains("\\") { return .address }
        // Dotted names: example.com, file.swift.
        if word.contains("."), word.first?.isLetter == true, word.last?.isLetter == true { return .address }
        if word.contains("_") || word.contains("`") { return .identifier }
        // camelCase or PascalCase-inside words.
        let interiorUppercase = word.dropFirst().contains(where: \.isUppercase)
        return interiorUppercase && word.contains(where: \.isLowercase) ? .identifier : nil
    }
}
