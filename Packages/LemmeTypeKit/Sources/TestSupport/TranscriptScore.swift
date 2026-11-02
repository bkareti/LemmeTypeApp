/// Every accuracy number for one hypothesis against its human reference:
/// word and character error rates, the edits behind them, and two
/// hallucination signals. Only numbers and flags — no text — so a score can
/// be written to a report.
public struct TranscriptScore: Codable, Equatable, Sendable {
    public let words: EditAlignment
    /// Words again after ``NumberNormalizer`` on both sides, so "1911" and "nineteen eleven" match.
    public let numberNormalizedWords: EditAlignment
    public let characters: EditAlignment
    /// The reference has no speech (silence, noise only) but text came out.
    public let textWithoutSpeech: Bool
    /// The same phrase repeats more often in a row than the reference says it,
    /// at least ``minimumLoopRepeats`` times — the decoding loop Whisper falls into.
    public let repetitionLoop: Bool

    /// Repeats in a row that count as a loop.
    public static let minimumLoopRepeats = 3
    /// The longest phrase, in words, checked for loops.
    static let longestLoopPhrase = 4

    public var wordErrorRate: Double { words.errorRate }
    public var numberNormalizedWordErrorRate: Double { numberNormalizedWords.errorRate }
    public var characterErrorRate: Double { characters.errorRate }
    /// Words that were never said ÷ reference words.
    public var insertionRate: Double { words.insertionRate }
    public var hallucinated: Bool { textWithoutSpeech || repetitionLoop }

    public init(
        words: EditAlignment, numberNormalizedWords: EditAlignment, characters: EditAlignment,
        textWithoutSpeech: Bool, repetitionLoop: Bool
    ) {
        self.words = words
        self.numberNormalizedWords = numberNormalizedWords
        self.characters = characters
        self.textWithoutSpeech = textWithoutSpeech
        self.repetitionLoop = repetitionLoop
    }

    /// `reference` is the human reference; an empty one means the audio has no speech.
    public static func score(reference: String, hypothesis: String) -> TranscriptScore {
        let expected = TranscriptNormalizer.words(reference)
        let actual = TranscriptNormalizer.words(hypothesis)
        let hypothesisRepeats = longestRepeat(in: actual)
        return TranscriptScore(
            words: EditAlignment.align(reference: expected, hypothesis: actual),
            numberNormalizedWords: WordErrorRate.alignment(
                reference: NumberNormalizer.normalize(reference), hypothesis: NumberNormalizer.normalize(hypothesis)),
            characters: CharacterErrorRate.alignment(reference: reference, hypothesis: hypothesis),
            textWithoutSpeech: expected.isEmpty && !actual.isEmpty,
            repetitionLoop: hypothesisRepeats >= minimumLoopRepeats && hypothesisRepeats > longestRepeat(in: expected))
    }

    /// The most times any phrase of 1…``longestLoopPhrase`` words appears back to back.
    static func longestRepeat(in words: [String]) -> Int {
        var longest = words.isEmpty ? 0 : 1
        for length in 1...longestLoopPhrase where length * 2 <= words.count {
            var start = 0
            while start + length * 2 <= words.count {
                var copies = 1
                while start + length * (copies + 1) <= words.count,
                    words[start..<(start + length)]
                        == words[(start + length * copies)..<(start + length * (copies + 1))]
                {
                    copies += 1
                }
                longest = max(longest, copies)
                start += 1
            }
        }
        return longest
    }
}
