import Domain
import Foundation
import TestSupport
import Testing

/// E12-S3: the grammar option, its fixed instruction, and the Proper English mode.
struct GrammarCorrectionTests {
    private let grammar = StyleOptions(correctsGrammar: true)

    private func engine(text: String) -> FakeRecognitionEngine {
        FakeRecognitionEngine(id: .whisper, script: .init(text: text), supportedLanguages: ["en"])
    }

    private func session(_ mode: DictationMode) throws -> DictationSession {
        try FileManager.default.createDirectory(
            at: TranscriptionPipelineTests.directory, withIntermediateDirectories: true)
        let url = TranscriptionPipelineTests.directory.appendingPathComponent("\(UUID().uuidString).placeholder")
        try Data("not audio".utf8).write(to: url)
        return DictationSession(
            audio: RecordedAudio(fileURL: url, duration: 2, format: .speech),
            target: ActivationTarget(
                processIdentifier: 42, bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit",
                focusedElement: nil),
            mode: mode.writingMode, dictationMode: mode, language: mode.language ?? "en-US")
    }

    private func review(_ outcome: DictationOutcome) -> DictationReview? {
        if case .review(let review, _) = outcome { return review }
        return nil
    }

    // MARK: The option

    @Test func itIsOffByDefaultAndOffMeansNoRewrite() {
        #expect(!StyleOptions().correctsGrammar)
        #expect(StyleOptions.none.isNone)
        #expect(StyleInstruction.make(.none) == nil)
        #expect(!grammar.isNone)
    }

    @Test func theIdentifierChangesOnlyWhenItIsOn() {
        #expect(StyleOptions.none.identifier == "none")
        #expect(StyleOptions(tone: .casual).identifier == "casual-plain-text-original")
        #expect(grammar.identifier == "neutral-plain-text-original-grammar")
        #expect(DiagnosticValue.isSafeIdentifier(grammar.identifier))
    }

    @Test func aModeSavedBeforeThisOptionLoadsWithItOff() throws {
        let saved = Data(#"{"tone":"professional","format":"email","length":"concise"}"#.utf8)
        let options = try JSONDecoder().decode(StyleOptions.self, from: saved)
        #expect(options == StyleOptions(tone: .professional, format: .email, length: .concise))
        #expect(!options.correctsGrammar)
    }

    @Test func itSurvivesSavingAndLoading() throws {
        let decoded = try JSONDecoder().decode(StyleOptions.self, from: JSONEncoder().encode(grammar))
        #expect(decoded == grammar)
    }

    @Test func exactDictationNeverCorrects() {
        let mode = DictationMode(name: "Mine", writingMode: .exact, style: grammar)
        #expect(mode.effectiveStyle == .none)
    }

    // MARK: The instruction

    @Test func theInstructionIsFixedAndKeepsTheFacts() throws {
        let instruction = try #require(StyleInstruction.make(grammar))
        #expect(instruction == StyleInstruction.make(grammar), "wording must be deterministic")
        #expect(instruction.hasPrefix("Correct the grammar, spelling, and punctuation"))
        #expect(instruction.contains("keep the speaker's own words"))
        #expect(instruction.contains("name, number, date, negation"))
        #expect(instruction.contains("Do not add facts"))
        #expect(!instruction.contains("Rewrite the passage"))
    }

    @Test func itCombinesWithAToneWithoutChangingOtherStyles() throws {
        let combined = try #require(StyleInstruction.make(StyleOptions(tone: .professional, correctsGrammar: true)))
        #expect(combined.hasPrefix("Rewrite the passage in a professional"))
        #expect(combined.contains("Also correct its grammar"))
        let plain = try #require(StyleInstruction.make(StyleOptions(tone: .professional)))
        #expect(!plain.contains("grammar"), "existing styles keep their exact wording")
    }

    // MARK: Proper English

    @Test func properEnglishIsABuiltInEnglishCleanMode() {
        let mode = DictationMode.properEnglish
        #expect(mode.id.rawValue == "proper-english")
        #expect(mode.id.isBuiltIn)
        #expect(mode.language == "en-US")
        #expect(mode.speechOutput == .original)
        #expect(mode.writingMode == .clean)
        #expect(mode.effectiveStyle == grammar)
        #expect(mode.engine == nil, "recognition stays on the local engines")
    }

    @Test func capitalisingADayIsNotAChangedDate() {
        #expect(PreservationChecker.violations(original: "See you on friday.", rewritten: "See you on Friday.").isEmpty)
        #expect(
            PreservationChecker.violations(original: "See you on friday.", rewritten: "See you on Monday.")
                == [.dateChanged])
    }

    // MARK: The pipeline

    @Test func dictationIsCorrectedAndEndsInAReview() async throws {
        let rewriter = FakeTextRewriter(script: .text("He goes to the office on Friday."))
        let delivery = FakeTextDelivery()
        let pipeline = TranscriptionPipeline(
            engines: [engine(text: "he go to office on friday")], delivery: delivery, rewriter: rewriter)
        let outcome = await pipeline.process(try session(.properEnglish)) { _ in }

        let result = try #require(review(outcome))
        #expect(result.isRewritten)
        #expect(result.text == "He goes to the office on Friday.")
        #expect(result.original == "He go to office on friday.", "the original is one tap away")
        #expect(rewriter.instructions == [StyleInstruction.make(grammar)])
        #expect(rewriter.instructions.allSatisfy { !$0.contains("office") }, "dictated text is only the passage")
        #expect(rewriter.languages.allSatisfy { $0.hasPrefix("en") })
        #expect(delivery.delivered.isEmpty, "nothing is delivered until the user chooses")
    }

    @Test func aModeWithoutTheOptionNeverCallsTheModel() async throws {
        let rewriter = FakeTextRewriter(script: .text("Changed."))
        let pipeline = TranscriptionPipeline(
            engines: [engine(text: "ship it")], delivery: FakeTextDelivery(), rewriter: rewriter)
        _ = await pipeline.process(try session(.clean)) { _ in }
        #expect(rewriter.rewriteCount == 0)
    }

    @Test(arguments: [
        ("send 3 files to Priya", "Send 4 files to Priya.", "number"),
        ("meet Priya on Friday", "Meet Priya on Monday.", "date"),
        ("do not send it", "Do send it.", "negation"),
        ("tell Priya today", "Tell Ravi today.", "name"),
    ])
    func aCorrectionThatChangesAFactIsRejected(spoken: String, rewritten: String, fact: String) async throws {
        let rewriter = FakeTextRewriter(script: .text(rewritten))
        let pipeline = TranscriptionPipeline(
            engines: [engine(text: spoken)], delivery: FakeTextDelivery(), rewriter: rewriter)
        let outcome = await pipeline.process(try session(.properEnglish)) { _ in }
        let result = try #require(review(outcome), "\(fact)")
        #expect(!result.isRewritten, "\(fact)")
        #expect(result.text == result.original, "\(fact)")
        guard case .meaningChanged = result.notice else {
            Issue.record("expected meaningChanged for \(fact), got \(String(describing: result.notice))")
            return
        }
    }

    @Test func withoutTheOnDeviceModelTheCleanedTextIsKeptWithANotice() async throws {
        let rewriter = FakeTextRewriter(availability: .deviceNotEligible)
        let pipeline = TranscriptionPipeline(
            engines: [engine(text: "um he go home")], delivery: FakeTextDelivery(), rewriter: rewriter)
        let outcome = await pipeline.process(try session(.properEnglish)) { _ in }
        let result = try #require(review(outcome))
        #expect(!result.isRewritten)
        #expect(result.text == "He go home.", "Clean Writing still ran")
        #expect(result.notice == .unavailable(.deviceNotEligible))
        #expect(rewriter.rewriteCount == 0)
    }
}
