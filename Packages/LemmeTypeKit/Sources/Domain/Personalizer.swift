/// Which personalization rule changed the text. Raw values are stable.
public enum PersonalizationRule: String, Sendable {
    /// A vocabulary term's spelling or letter case was applied.
    case vocabulary
    /// A spoken phrase was replaced by its written text.
    case replacement
}

/// One change made by the ``Personalizer``. In memory only: it holds dictated text.
public struct PersonalizationTransformation: Equatable, Sendable {
    public let rule: PersonalizationRule
    public let before: String
    public let after: String

    public init(rule: PersonalizationRule, before: String, after: String) {
        self.rule = rule
        self.before = before
        self.after = after
    }
}

public struct PersonalizationResult: Equatable, Sendable {
    public let text: String
    public let transformations: [PersonalizationTransformation]

    public init(text: String, transformations: [PersonalizationTransformation]) {
        self.text = text
        self.transformations = transformations
    }
}

/// Applies vocabulary and replacements to written text (E4-S2, ADR 0020).
///
/// Pure and deterministic. Phrases match whole words, ignoring letter case;
/// the longest phrase wins (a replacement before a vocabulary spelling of the
/// same length); the text is scanned once, left to right, so replaced text is
/// never matched again. Runs after the writing mode, so the written forms are
/// exactly what the user typed.
public struct Personalizer: Sendable {
    private struct Phrase: Sendable {
        let length: Int
        let key: String
        let output: String
        let rule: PersonalizationRule
    }

    /// Phrases by their lower-cased first character, longest first.
    private let phrases: [Character: [Phrase]]

    public init(library: PersonalizationLibrary) {
        var all: [Phrase] = []
        for replacement in library.replacements {
            all.append(Self.phrase(replacement.spoken, output: replacement.written, rule: .replacement))
        }
        for entry in library.vocabulary {
            for spelling in [entry.term] + entry.soundsLike {
                all.append(Self.phrase(spelling, output: entry.term, rule: .vocabulary))
            }
        }
        var seen = Set<String>()
        var buckets: [Character: [Phrase]] = [:]
        // Stable sort: equal lengths keep replacements before vocabulary.
        for phrase in all.enumerated().sorted(by: { ($1.element.length, $0.offset) < ($0.element.length, $1.offset) })
            .map(\.element)
        where seen.insert(phrase.key).inserted {
            guard let first = phrase.key.first else { continue }
            buckets[first, default: []].append(phrase)
        }
        phrases = buckets
    }

    public var isEmpty: Bool { phrases.isEmpty }

    /// Adapter for the pipeline.
    public static func apply(_ text: String, library: PersonalizationLibrary) -> String {
        library.vocabulary.isEmpty && library.replacements.isEmpty
            ? text : Personalizer(library: library).apply(text).text
    }

    public func apply(_ text: String) -> PersonalizationResult {
        guard !phrases.isEmpty else { return PersonalizationResult(text: text, transformations: []) }
        let characters = Array(text)
        var output = ""
        var transformations: [PersonalizationTransformation] = []
        var index = 0
        while index < characters.count {
            if index == 0 || !Self.isWordCharacter(characters[index - 1]),
                let phrase = match(in: characters, at: index)
            {
                let original = String(characters[index..<index + phrase.length])
                if original != phrase.output {
                    transformations.append(
                        PersonalizationTransformation(rule: phrase.rule, before: original, after: phrase.output))
                }
                output += phrase.output
                index += phrase.length
            } else {
                output.append(characters[index])
                index += 1
            }
        }
        return PersonalizationResult(text: output, transformations: transformations)
    }

    private func match(in characters: [Character], at index: Int) -> Phrase? {
        guard let first = String(characters[index]).lowercased().first, let candidates = phrases[first] else {
            return nil
        }
        for phrase in candidates where index + phrase.length <= characters.count {
            let end = index + phrase.length
            guard end == characters.count || !Self.isWordCharacter(characters[end]) else { continue }
            if String(characters[index..<end]).lowercased() == phrase.key {
                return phrase
            }
        }
        return nil
    }

    private static func phrase(_ spoken: String, output: String, rule: PersonalizationRule) -> Phrase {
        let normalized = PersonalizationText.normalizedPhrase(spoken)
        return Phrase(length: normalized.count, key: normalized.lowercased(), output: output, rule: rule)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
