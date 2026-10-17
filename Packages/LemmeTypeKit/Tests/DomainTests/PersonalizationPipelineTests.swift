import Domain
import Foundation
import TestSupport
import Testing

/// E4-S2 and E4-S3 through the pipeline: personalization runs after the
/// writing mode, snippets replace the whole utterance, hints reach the engine.
struct PersonalizationPipelineTests {
    private static func library() throws -> PersonalizationLibrary {
        try PersonalizationLibrary(
            vocabulary: [VocabularyEntry(term: "LemmeType", soundsLike: ["lemme type"])],
            replacements: [Replacement(spoken: "my email", written: "pat@example.com")],
            snippets: [Snippet(trigger: "sign off", expansion: "Best regards,\nPat")])
    }

    private func session(
        mode: WritingMode, purpose: SessionPurpose = .dictation, context: ContextCapture = .notRequested
    ) throws -> DictationSession {
        let base = try TranscriptionPipelineTests.makeSession(mode: mode)
        let target = try #require(base.target).with(context: context)
        return DictationSession(
            audio: base.audio, target: target, mode: mode, purpose: purpose, language: "en-US",
            personalization: try Self.library())
    }

    private func deliver(
        _ spoken: String, mode: WritingMode, context: ContextCapture = .notRequested,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) async throws -> (delivered: [String], engine: FakeRecognitionEngine) {
        let engine = FakeRecognitionEngine(id: .appleSpeech, script: .init(text: spoken))
        let delivery = FakeTextDelivery()
        let pipeline = TranscriptionPipeline(engines: [engine], delivery: delivery, diagnostics: diagnostics)
        _ = await pipeline.process(try session(mode: mode, context: context)) { _ in }
        return (delivery.delivered, engine)
    }

    @Test func vocabularyAppliesInExactWithoutOtherChanges() async throws {
        let result = try await deliver("i use lemme type  daily um", mode: .exact)
        #expect(result.delivered == ["i use LemmeType daily um"])
    }

    @Test func replacementAppliesAfterCleanWriting() async throws {
        let result = try await deliver("send it to my email", mode: .clean)
        #expect(result.delivered == ["Send it to pat@example.com."])
    }

    @Test func snippetIsDeliveredExactlyInEitherMode() async throws {
        #expect(try await deliver("Sign off.", mode: .clean).delivered == ["Best regards,\nPat"])
        #expect(try await deliver("sign off", mode: .exact).delivered == ["Best regards,\nPat"])
        #expect(try await deliver("please sign off", mode: .clean).delivered == ["Please sign off."])
    }

    @Test func snippetWithContextOnlyGetsSpacing() async throws {
        let caret = TextSelection(location: 12, length: 0)
        let context = try #require(CursorContext(precedingText: "Thanks a lot", followingText: "", selection: caret))
        let result = try await deliver(
            "sign off", mode: .clean, context: .captured(context, purpose: .formatting))
        #expect(result.delivered == [" Best regards,\nPat"])
    }

    @Test func vocabularyTermsAreRecognitionHints() async throws {
        let result = try await deliver("hello", mode: .exact)
        #expect(result.engine.lastHints == ["LemmeType"])
    }

    @Test func emptyLibraryKeepsEpicTwoOutputAndSendsNoHints() async throws {
        let engine = FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "send it to my email"))
        let delivery = FakeTextDelivery()
        _ = await TranscriptionPipeline(engines: [engine], delivery: delivery)
            .process(try TranscriptionPipelineTests.makeSession(mode: .clean)) { _ in }
        #expect(delivery.delivered == ["Send it to my email."])
        #expect(engine.lastHints.isEmpty)
    }

    @Test func voiceEditingNeverExpandsSnippetsOrSendsHints() async throws {
        let selection = TextSelection(location: 0, length: 5)
        let context = try #require(
            CursorContext(precedingText: "", followingText: "", selection: selection, selectedText: "Hello"))
        let engine = FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "sign off"))
        let rewriter = FakeTextRewriter()
        let delivery = FakeTextDelivery()
        let pipeline = TranscriptionPipeline(engines: [engine], delivery: delivery, rewriter: rewriter)
        _ = await pipeline.process(
            try session(mode: .clean, purpose: .editing, context: .captured(context, purpose: .editing))
        ) { _ in }
        #expect(engine.lastHints.isEmpty)
        #expect(delivery.delivered.first != "Best regards,\nPat")
        #expect(rewriter.instructions == ["sign off"])
    }

    @Test func diagnosticsCountChangesWithoutWords() async throws {
        let diagnostics = RecordingDiagnostics()
        _ = try await deliver("lemme type to my email", mode: .exact, diagnostics: diagnostics)
        let delivered = try #require(diagnostics.events.first { $0.name == "session.delivered" })
        #expect(delivered.attributes["personalizations"] == .count(2))
        #expect(delivered.attributes["snippet"] == .flag(false))

        let snippetDiagnostics = RecordingDiagnostics()
        _ = try await deliver("sign off", mode: .exact, diagnostics: snippetDiagnostics)
        let snippet = try #require(snippetDiagnostics.events.first { $0.name == "session.delivered" })
        #expect(snippet.attributes["snippet"] == .flag(true))

        let report = String(describing: diagnostics.events + snippetDiagnostics.events).lowercased()
        for word in ["lemmetype", "pat@example", "best regards", "sign off"] {
            #expect(!report.contains(word))
        }
    }
}
