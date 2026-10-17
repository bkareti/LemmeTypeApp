import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

/// E3-S5: the pipeline turns a spoken instruction into a rewrite of the selection.
struct VoiceEditingPipelineTests {
    static func editSession(selected: String? = "Meet on Tuesday at noon") throws -> DictationSession {
        let base = try TranscriptionPipelineTests.makeSession()
        var target = try #require(base.target)
        if let selected {
            let context = try #require(
                CursorContext(
                    precedingText: "", followingText: "", selection: TextSelection(location: 0, length: selected.count),
                    selectedText: selected))
            target = target.with(context: .captured(context, purpose: .editing))
        }
        return DictationSession(audio: base.audio, target: target, mode: .clean, purpose: .editing, language: "en-US")
    }

    private func pipeline(
        rewriter: FakeTextRewriter?, delivery: FakeTextDelivery, instruction: String = "make it shout",
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) -> (TranscriptionPipeline, FakeRecognitionEngine) {
        let engine = FakeRecognitionEngine(id: .appleSpeech, script: .init(text: instruction))
        return (
            TranscriptionPipeline(engines: [engine], delivery: delivery, rewriter: rewriter, diagnostics: diagnostics),
            engine
        )
    }

    @Test func replacesSelectionOnce() async throws {
        let delivery = FakeTextDelivery()
        let rewriter = FakeTextRewriter()
        let (pipeline, _) = pipeline(rewriter: rewriter, delivery: delivery)
        let session = try Self.editSession()
        let phases = UpdatesLog()

        let outcome = await pipeline.process(session) { phases.append($0) }

        #expect(outcome == .delivered(.accessibility))
        #expect(delivery.delivered == ["MEET ON TUESDAY AT NOON"])
        #expect(rewriter.instructions == ["make it shout"])  // the instruction is not cleaned into a sentence
        #expect(phases.values.contains(.phase(.rewriting)))
        #expect(!phases.values.contains(.phase(.writing)))
        #expect(!TranscriptionPipelineTests.exists(session))
    }

    @Test func refusalKeepsOriginal() async throws {
        let delivery = FakeTextDelivery()
        let (pipeline, _) = pipeline(rewriter: FakeTextRewriter(script: .failure(.refused)), delivery: delivery)

        let outcome = await pipeline.process(try Self.editSession()) { _ in }

        #expect(
            outcome
                == .needsAttention(.rewriteFailed(.refused), engine: .appleSpeech, alternatives: [], transcript: nil))
        #expect(delivery.delivered.isEmpty)
        #expect(DictationIssue.rewriteFailed(.refused).actions(alternatives: []) == [.discard])
        #expect(DictationIssue.rewriteFailed(.busy).actions(alternatives: []) == [.retry, .discard])
    }

    @Test func unavailableModelIsReported() async throws {
        let delivery = FakeTextDelivery()
        let (pipeline, _) = pipeline(rewriter: FakeTextRewriter(availability: .notEnabled), delivery: delivery)

        let outcome = await pipeline.process(try Self.editSession()) { _ in }

        #expect(
            outcome
                == .needsAttention(
                    .rewriterUnavailable(.notEnabled), engine: .appleSpeech, alternatives: [], transcript: nil))
        #expect(delivery.delivered.isEmpty)
    }

    @Test func silenceIsNoSpeech() async throws {
        let delivery = FakeTextDelivery()
        let rewriter = FakeTextRewriter()
        let (pipeline, _) = pipeline(rewriter: rewriter, delivery: delivery, instruction: "   ")

        let outcome = await pipeline.process(try Self.editSession()) { _ in }

        #expect(
            outcome
                == .needsAttention(
                    .recognitionFailed(.noSpeechDetected), engine: .appleSpeech, alternatives: [], transcript: nil))
        #expect(rewriter.rewriteCount == 0)
    }

    @Test func cancellationDuringRewriteDeliversNothing() async throws {
        let delivery = FakeTextDelivery()
        let (pipeline, _) = pipeline(rewriter: FakeTextRewriter(delay: .seconds(5)), delivery: delivery)
        let session = try Self.editSession()

        let task = Task { await pipeline.process(session) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        #expect(await task.value == .cancelled)
        #expect(delivery.delivered.isEmpty)
    }

    @Test func editingIssueIsCheckedBeforeRecording() async throws {
        let (ready, _) = pipeline(rewriter: FakeTextRewriter(), delivery: FakeTextDelivery())
        let session = try Self.editSession()
        #expect(await ready.editingIssue(for: session.target, language: "en-US") == nil)

        let noSelection = try Self.editSession(selected: nil).target
        #expect(await ready.editingIssue(for: noSelection, language: "en-US") == .editingUnavailable(.noSelection))
        #expect(await ready.editingIssue(for: nil, language: "en-US") == .editingUnavailable(.unreadable))
        let excluded = noSelection?.with(context: .blocked(.excludedApp, purpose: .editing))
        #expect(await ready.editingIssue(for: excluded, language: "en-US") == .editingUnavailable(.excludedApp))

        let (off, _) = pipeline(
            rewriter: FakeTextRewriter(availability: .deviceNotEligible), delivery: FakeTextDelivery())
        #expect(
            await off.editingIssue(for: session.target, language: "en-US") == .rewriterUnavailable(.deviceNotEligible))
        let (none, _) = pipeline(rewriter: nil, delivery: FakeTextDelivery())
        #expect(await none.editingIssue(for: session.target, language: "en-US") == .rewriterUnavailable(.unavailable))
    }

    @Test func editingNeverReachesDiagnostics() async throws {
        let canary = "CANARY-SELECTION-77ab"
        let diagnostics = RecordingDiagnostics()
        let delivery = FakeTextDelivery()
        let (pipeline, _) = pipeline(
            rewriter: FakeTextRewriter(script: .text("CANARY-RESULT-19fe")), delivery: delivery,
            instruction: "CANARY-INSTRUCTION-3c0d", diagnostics: diagnostics)

        _ = await pipeline.process(try Self.editSession(selected: canary)) { _ in }

        let dump = String(describing: diagnostics.events)
        for secret in [canary, "CANARY-RESULT-19fe", "CANARY-INSTRUCTION-3c0d"] {
            #expect(!dump.contains(secret))
        }
        #expect(dump.contains("editing"))
        #expect(dump.contains("rewriteSeconds"))
    }
}

private final class UpdatesLog: Sendable {
    private let log = Mutex<[ProcessingUpdate]>([])
    var values: [ProcessingUpdate] { log.withLock { $0 } }
    func append(_ update: ProcessingUpdate) { log.withLock { $0.append(update) } }
}
