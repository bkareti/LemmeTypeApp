import Domain
import TestSupport
import Testing

/// How the Mac's opt-in evaluation and the iPhone and iPad on-device evaluation read their choices.
struct EvaluationOptionsTests {
    @Test func builtInModesAndStyles() throws {
        #expect(try EvaluationOptions.mode() == .clean)
        #expect(try EvaluationOptions.mode("exact") == .exact)
        #expect(try EvaluationOptions.mode("message") == .message)

        let styled = try EvaluationOptions.mode(style: "professional-bullet-list-concise")
        #expect(styled.id.rawValue == "style-professional-bullet-list-concise")
        #expect(styled.writingMode == .clean)
        #expect(styled.style == StyleOptions(tone: .professional, format: .bulletList, length: .concise))
    }

    @Test func unknownChoicesAreRefusedByName() {
        #expect(throws: EvaluationOptions.Problem.unknownMode("fancy")) { try EvaluationOptions.mode("fancy") }
        #expect(throws: EvaluationOptions.Problem.unknownStyle("loud-email")) {
            try EvaluationOptions.mode(style: "loud-email")
        }
        #expect(throws: EvaluationOptions.Problem.unknownTask("summarize")) {
            try EvaluationOptions.task("summarize")
        }
    }

    @Test func tasksAndLanguages() throws {
        #expect(try EvaluationOptions.task(nil) == .transcribe)
        #expect(try EvaluationOptions.task("translate-to-english") == .translateToEnglish)
        #expect(EvaluationOptions.languages(nil) == nil)
        #expect(EvaluationOptions.languages(" , ") == nil)
        #expect(EvaluationOptions.languages("hi, te") == ["hi", "te"])
    }
}
