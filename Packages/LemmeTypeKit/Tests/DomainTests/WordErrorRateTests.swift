import TestSupport
import Testing

struct WordErrorRateTests {
    @Test func identicalTextIgnoringCaseAndPunctuationIsZero() {
        #expect(WordErrorRate.of(reference: "Ship it on Wednesday.", hypothesis: "ship it on wednesday") == 0)
    }

    @Test func countsSubstitutionsInsertionsAndDeletions() {
        #expect(WordErrorRate.of(reference: "a b c d", hypothesis: "a x c d") == 0.25)
        #expect(WordErrorRate.of(reference: "a b c d", hypothesis: "a b c d e") == 0.25)
        #expect(WordErrorRate.of(reference: "a b c d", hypothesis: "a c d") == 0.25)
        #expect(WordErrorRate.of(reference: "", hypothesis: "") == 0)
        #expect(WordErrorRate.of(reference: "", hypothesis: "noise") == 1)
    }
}
