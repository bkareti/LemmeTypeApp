import TestSupport
import Testing

/// The accuracy metrics of the evaluation harness: one normalization, the
/// edit split behind every rate, character error rate, and hallucination flags.
struct TranscriptMetricsTests {
    @Test func normalizationIgnoresCasePunctuationAndCurlyApostrophes() {
        #expect(TranscriptNormalizer.words("Don’t ship it, OK?") == ["don't", "ship", "it", "ok"])
        #expect(TranscriptNormalizer.normalize("  Ship   it.  ") == "ship it")
        #expect(TranscriptNormalizer.normalize("…") == "")
    }

    @Test func normalizationComposesAndDropsZeroWidthCharacters() {
        let decomposed = "cafe\u{0301}"
        #expect(TranscriptNormalizer.normalize(decomposed) == TranscriptNormalizer.normalize("café"))
        // A zero-width non-joiner inside a Hindi word does not make it a different word.
        #expect(TranscriptNormalizer.words("क्\u{200C}ष") == TranscriptNormalizer.words("क्ष"))
    }

    @Test func indicWordsKeepTheirVowelSignsAndLoseTheDanda() {
        #expect(TranscriptNormalizer.words("मैं कल आऊँगा।") == ["मैं", "कल", "आऊँगा"])
        #expect(TranscriptNormalizer.words("నేను రేపు వస్తాను.") == ["నేను", "రేపు", "వస్తాను"])
        #expect(TranscriptNormalizer.words("ನಾನು ನಾಳೆ ಬರುತ್ತೇನೆ") == ["ನಾನು", "ನಾಳೆ", "ಬರುತ್ತೇನೆ"])
        #expect(TranscriptNormalizer.words("நான் நாளை வருவேன்") == ["நான்", "நாளை", "வருவேன்"])
        #expect(TranscriptNormalizer.words("१२ बजे") == ["१२", "बजे"])
    }

    @Test func alignmentSplitsEditsByKind() {
        let words = EditAlignment.align(reference: ["a", "b", "c", "d"], hypothesis: ["a", "x", "c", "d", "e"])
        #expect(words == EditAlignment(referenceLength: 4, substitutions: 1, deletions: 0, insertions: 1))
        #expect(words.errorRate == 0.5)
        #expect(words.insertionRate == 0.25)

        let dropped = EditAlignment.align(reference: ["a", "b", "c"], hypothesis: ["a"])
        #expect(dropped.deletions == 2)
        #expect(dropped.edits == 2)
        #expect(EditAlignment.align(reference: [String](), hypothesis: ["noise"]).insertionRate == 1)
    }

    @Test func wordErrorRateKeepsItsMeaning() {
        #expect(WordErrorRate.of(reference: "Ship it on Wednesday.", hypothesis: "ship it on wednesday") == 0)
        #expect(WordErrorRate.of(reference: "I don't know", hypothesis: "I don’t know") == 0)
    }

    @Test func characterErrorRateCountsCharactersIncludingSpaces() {
        #expect(CharacterErrorRate.of(reference: "kitten", hypothesis: "sitting") == 0.5)
        #expect(CharacterErrorRate.of(reference: "a b", hypothesis: "ab") == 1.0 / 3)
        #expect(CharacterErrorRate.of(reference: "", hypothesis: "") == 0)
        #expect(CharacterErrorRate.of(reference: "", hypothesis: "x") == 1)
    }

    @Test func oneWrongVowelSignFailsTheWordButBarelyMovesCharacterErrorRate() {
        // వస్తాను → వస్తాన (the final vowel sign dropped).
        let score = TranscriptScore.score(reference: "నేను రేపు వస్తాను", hypothesis: "నేను రేపు వస్తాన")
        #expect(score.wordErrorRate == 1.0 / 3)
        #expect(score.characterErrorRate < 0.1)
        #expect(score.characterErrorRate > 0)
    }

    @Test func textFromAudioWithoutSpeechIsAHallucination() {
        let invented = TranscriptScore.score(reference: "", hypothesis: "Thank you for watching.")
        #expect(invented.textWithoutSpeech)
        #expect(invented.hallucinated)

        let quiet = TranscriptScore.score(reference: "", hypothesis: "")
        #expect(!quiet.hallucinated)
        #expect(quiet.wordErrorRate == 0)
    }

    @Test func aRepeatingPhraseIsALoopUnlessTheSpeakerRepeatedIt() {
        let loop = TranscriptScore.score(
            reference: "thank you", hypothesis: "Thank you. Thank you. Thank you. Thank you.")
        #expect(loop.repetitionLoop)
        #expect(loop.hallucinated)
        #expect(loop.insertionRate == 3)

        #expect(!TranscriptScore.score(reference: "no no no", hypothesis: "no, no, no").repetitionLoop)
        #expect(!TranscriptScore.score(reference: "very good", hypothesis: "very very good").repetitionLoop)
        #expect(TranscriptScore.score(reference: "go", hypothesis: "go go go go").repetitionLoop)
    }
}
