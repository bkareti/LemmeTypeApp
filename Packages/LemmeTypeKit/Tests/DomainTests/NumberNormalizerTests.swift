import TestSupport
import Testing

/// Numbers are compared as digits on both sides, whichever way they were written.
struct NumberNormalizerTests {
    @Test(arguments: [
        ("twenty-three people", "23 people"),
        ("one hundred and five", "105"),
        ("Two thousand twenty four", "2024"),
        ("three million", "3000000"),
        ("nineteen eleven", "1911"),
        ("in twenty twenty-four", "in 2024"),
        ("twelve hundred", "1200"),
        ("zero", "0"),
        ("one", "1"),
    ])
    func spokenNumbersBecomeDigits(spoken: String, digits: String) {
        #expect(NumberNormalizer.normalize(spoken) == digits)
    }

    @Test func otherScriptsDigitsAndSeparatorsAreFolded() {
        #expect(NumberNormalizer.normalize("१२ बजे") == "12 बजे")
        #expect(NumberNormalizer.normalize("౧౯౧౧") == "1911")
        #expect(NumberNormalizer.normalize("1,000 and 12,50") == "1000 and 12,50")
    }

    @Test func everythingElseIsLeftAlone() {
        #expect(NumberNormalizer.normalize("Gate Ten closes, OK?") == "Gate 10 closes, OK?")
        #expect(NumberNormalizer.normalize("five six seven") == "five six seven")
        #expect(NumberNormalizer.normalize("someone and anyone") == "someone and anyone")
        #expect(NumberNormalizer.normalize("hundred") == "hundred")
        #expect(NumberNormalizer.normalize("नमस्ते") == "नमस्ते")
    }

    @Test func aDigitReferenceMatchesASpokenHypothesisOnlyAfterNormalization() {
        let reference = "The ship sank in 1911 with 23 people."
        let hypothesis = "the ship sank in nineteen eleven with twenty three people"
        #expect(WordErrorRate.of(reference: reference, hypothesis: hypothesis) > 0.3)
        #expect(
            WordErrorRate.of(
                reference: NumberNormalizer.normalize(reference), hypothesis: NumberNormalizer.normalize(hypothesis))
                == 0)
    }
}
