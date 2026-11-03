import Domain
import Testing

struct RepetitionLoopTests {
    @Test func aPhraseRepeatedFourTimesIsCutToOneCopy() {
        let result = RepetitionLoop.collapse("Send it today. Thank you. Thank you. Thank you. Thank you.")
        #expect(result.text == "Send it today. Thank you.")
        #expect(result.removedCopies == 3)
    }

    @Test func threeCopiesAreWhatPeopleSayAndStay() {
        let text = "No, no, no, that is wrong."
        #expect(RepetitionLoop.collapse(text) == (text, 0))
    }

    @Test func textWithoutALoopComesBackUnchangedSpacingIncluded() {
        let text = "Ship it  on Wednesday.\nThanks"
        #expect(RepetitionLoop.collapse(text) == (text, 0))
    }

    @Test func caseAndPunctuationDoNotHideALoop() {
        let result = RepetitionLoop.collapse("okay Okay, OKAY. okay! fine")
        #expect(result.text == "okay fine")
        #expect(result.removedCopies == 3)
    }

    @Test func aLoopInAnIndicScriptIsCut() {
        let phrase = "मैं ठीक हूँ।"
        let result = RepetitionLoop.collapse(Array(repeating: phrase, count: 6).joined(separator: " ") + " बस")
        #expect(result.text == "मैं ठीक हूँ। बस")
        #expect(result.removedCopies == 5)
    }

    @Test func theShortestRepeatingPhraseIsKept() {
        // One word eight times, not a two-word phrase four times.
        #expect(RepetitionLoop.collapse("la la la la la la la la").text == "la")
    }

    @Test func phrasesLongerThanTheLimitAreNotChecked() {
        let phrase = (1...(RepetitionLoop.longestPhrase + 1)).map { "w\($0)" }.joined(separator: " ")
        let text = Array(repeating: phrase, count: 5).joined(separator: " ")
        #expect(RepetitionLoop.collapse(text).removedCopies == 0)
    }

    @Test func punctuationAloneIsNeverAPhrase() {
        let text = "Wait - - - - what"
        #expect(RepetitionLoop.collapse(text) == (text, 0))
    }

    @Test func longestRunReportsCopiesAndPhraseLength() {
        #expect(RepetitionLoop.longestRun(in: "a b c a b c a b c d") == .init(phraseLength: 3, copies: 3))
        #expect(RepetitionLoop.longestRun(in: "one two") == .init(phraseLength: 1, copies: 1))
        #expect(RepetitionLoop.longestRun(in: "") == .init(phraseLength: 1, copies: 0))
    }
}
