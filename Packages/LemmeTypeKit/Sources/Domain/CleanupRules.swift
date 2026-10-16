/// The Clean Writing rules. Each one edits `CleanupDocument.tokens` and
/// records every change it makes.
enum CleanupRules {
    // MARK: Spoken punctuation

    /// Multi-word commands first so "question mark" wins over "mark".
    static let spokenMarks: [(words: [String], mark: String)] = [
        (["new", "paragraph"], "\n\n"),
        (["new", "line"], "\n"),
        (["question", "mark"], "?"),
        (["exclamation", "mark"], "!"),
        (["exclamation", "point"], "!"),
        (["full", "stop"], "."),
        (["comma"], ","),
        (["semicolon"], ";"),
    ]

    static func spokenPunctuation(_ document: inout CleanupDocument) {
        var index = 0
        while index < document.tokens.count {
            guard index > 0, let match = spokenMark(at: index, in: document.tokens) else {
                index += 1
                continue
            }
            let previous = index - 1
            let spoken = document.tokens[index..<index + match.words.count].map(\.text).joined(separator: " ")
            document.tokens.removeSubrange(index..<index + match.words.count)
            if match.mark.hasPrefix("\n") {
                document.tokens.insert(
                    CleanupToken(leading: "", word: match.mark, trailing: "", protection: .verbatim), at: index)
                index += 1
            } else if !document.tokens[previous].isBreak {
                document.tokens[previous].trailing = mergedTrailing(document.tokens[previous].trailing, match.mark)
            }
            document.record(spoken, match.mark)
        }
        // "period" is a mark only at the very end, where it cannot be the noun.
        if document.tokens.count > 1, let last = document.tokens.last, last.lowercasedWord == "period",
            !last.isProtected, last.trailing.isEmpty || last.trailing == "."
        {
            document.tokens.removeLast()
            let end = document.tokens.count - 1
            document.tokens[end].trailing = mergedTrailing(document.tokens[end].trailing, ".")
            document.record(last.text, ".")
        }
    }

    private static func spokenMark(at index: Int, in tokens: [CleanupToken]) -> (words: [String], mark: String)? {
        spokenMarks.first { candidate in
            guard index + candidate.words.count <= tokens.count else { return false }
            return candidate.words.enumerated().allSatisfy { offset, word in
                let token = tokens[index + offset]
                return !token.isProtected && token.lowercasedWord == word && token.leading.isEmpty
            }
        }
    }

    /// Replaces a trailing comma the recogniser added with the spoken mark.
    private static func mergedTrailing(_ trailing: String, _ mark: String) -> String {
        let kept = trailing.filter { !",.;!?".contains($0) }
        return kept + mark
    }

    // MARK: Self-correction

    static let correctionMarkers: [[String]] = [["sorry"], ["i", "mean"], ["no", "wait"]]
    static let weekdays: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let months: Set<String> = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
        "november", "december",
    ]
    static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
        "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred",
    ]

    enum WordKind { case weekday, month, number }

    static func kind(of token: CleanupToken) -> WordKind? {
        let word = token.lowercasedWord
        if weekdays.contains(word) { return .weekday }
        if word.allSatisfy(\.isNumber) || numberWords.contains(word) { return .number }
        if months.contains(word) && word != "may" && word != "march" { return .month }
        return nil
    }

    /// `X <marker> Y` → `Y` only when X and Y are single words of the same
    /// kind and the marker is set off by dashes or commas or stands alone
    /// between them. Everything else ("sorry I'm late", "I mean it") is left alone.
    static func selfCorrection(_ document: inout CleanupDocument) {
        var index = 1
        while index < document.tokens.count {
            guard let replaced = correction(at: index, in: document.tokens) else {
                index += 1
                continue
            }
            let before = document.tokens[replaced.start...replaced.end].map(\.text).joined(separator: " ")
            var corrected = document.tokens[replaced.end]
            corrected.leading = document.tokens[replaced.start].leading
            document.tokens.replaceSubrange(replaced.start...replaced.end, with: [corrected])
            document.record(before, corrected.text)
            index = replaced.start + 1
        }
    }

    private static func correction(at index: Int, in tokens: [CleanupToken]) -> (start: Int, end: Int)? {
        for marker in correctionMarkers {
            var cursor = index
            if isDash(tokens[cursor]) { cursor += 1 }
            guard cursor + marker.count < tokens.count,
                marker.enumerated().allSatisfy({ tokens[cursor + $0.offset].lowercasedWord == $0.element })
            else { continue }
            var next = cursor + marker.count
            if next < tokens.count, isDash(tokens[next]) { next += 1 }
            let start = index - 1
            guard next < tokens.count, let kind = kind(of: tokens[start]), kind == self.kind(of: tokens[next]),
                tokens[start].trailing.allSatisfy({ $0 == "," }),
                tokens[cursor + marker.count - 1].trailing.allSatisfy({ $0 == "," })
            else { continue }
            return (start, next)
        }
        return nil
    }

    private static func isDash(_ token: CleanupToken) -> Bool {
        token.word == "—" || token.word == "–" || token.word == "-"
    }

    // MARK: Fillers and repeats

    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "mm"]

    static func fillerWords(_ document: inout CleanupDocument) {
        var index = 0
        while index < document.tokens.count {
            let token = document.tokens[index]
            guard !token.isProtected, fillers.contains(token.lowercasedWord) else {
                index += 1
                continue
            }
            document.tokens.remove(at: index)
            let terminal = token.trailing.filter { ".?!".contains($0) }
            if !terminal.isEmpty, index > 0 {
                document.tokens[index - 1].trailing = mergedTrailing(document.tokens[index - 1].trailing, terminal)
            }
            if index < document.tokens.count, !token.leading.isEmpty {
                document.tokens[index].leading = token.leading + document.tokens[index].leading
            }
            document.record(token.text, "")
        }
    }

    /// Doubles that are grammatical ("had had", "that that") are kept.
    static let legitimateDoubles: Set<String> = ["had", "that", "is", "do", "no", "very", "so", "bye", "ha", "knock"]

    static func repeatedWords(_ document: inout CleanupDocument) {
        var index = 1
        while index < document.tokens.count {
            let previous = document.tokens[index - 1]
            let current = document.tokens[index]
            let isRepeat =
                !previous.isProtected && !current.isProtected && !previous.isBreak
                && previous.trailing.isEmpty && current.leading.isEmpty && !previous.word.isEmpty
                && previous.lowercasedWord == current.lowercasedWord
                && !legitimateDoubles.contains(current.lowercasedWord)
            if isRepeat {
                document.tokens.remove(at: index)
                document.tokens[index - 1].trailing = current.trailing
                document.record(previous.text + " " + current.text, document.tokens[index - 1].text)
            } else {
                index += 1
            }
        }
    }

    // MARK: Capitalization and terminal punctuation

    static let pronounI: Set<String> = ["i", "i'm", "i've", "i'll", "i'd", "i’m", "i’ve", "i’ll", "i’d"]

    static func capitalization(_ document: inout CleanupDocument) {
        var startsSentence = true
        for index in document.tokens.indices {
            let token = document.tokens[index]
            if token.isBreak {
                startsSentence = true
                continue
            }
            var updated = token
            if !token.isProtected, let first = token.word.first, first.isLowercase,
                startsSentence || pronounI.contains(token.lowercasedWord)
            {
                updated.word = first.uppercased() + token.word.dropFirst()
            }
            if updated != token {
                document.tokens[index] = updated
                document.record(token.text, updated.text)
            }
            if !token.word.isEmpty && !isDash(token) {
                startsSentence = token.trailing.contains { ".?!".contains($0) }
            }
        }
    }

    static func terminalPunctuation(_ document: inout CleanupDocument) {
        guard let index = document.tokens.lastIndex(where: { !$0.isBreak }) else { return }
        let token = document.tokens[index]
        let terminators: Set<Character> = [".", "?", "!", "…", ":", ";"]
        // A period may follow an identifier, but not a number, address, or
        // quote, where it could read as part of the protected text.
        guard token.protection == nil || token.protection == .identifier,
            !token.trailing.contains(where: terminators.contains),
            token.word.last.map({ !terminators.contains($0) }) ?? false
        else { return }
        document.tokens[index].trailing = token.trailing.filter { $0 != "," } + "."
        document.record(token.text, document.tokens[index].text)
    }
}
