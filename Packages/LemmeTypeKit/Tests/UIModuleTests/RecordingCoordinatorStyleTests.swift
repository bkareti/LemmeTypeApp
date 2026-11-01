import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E10-S4: reviewing a rewrite — Insert, Use Original, Regenerate, Copy, Discard.
@MainActor
struct RecordingCoordinatorStyleTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let processor = RecordingSpy()
    private let copier = FakeTextDelivery()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-CoordinatorStyle-\(UUID().uuidString)", isDirectory: true))
    private let style = StyleOptions(tone: .professional, format: .email)

    private func makeCoordinator() -> RecordingCoordinator {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage,
                permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: feedback, preferences: FakePreferences(), textCopier: copier,
            finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }

    private var leftoverFiles: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
    }

    private func speak(_ coordinator: RecordingCoordinator) async {
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        source.emitTone(seconds: 0.5)
        coordinator.handle(.stop)
        await coordinator.settle()
    }

    private func rewritten(
        _ text: String = "Hi,\n\nPlease send it.\n\nThanks,", notice: RewriteNotice? = nil
    ) -> DictationOutcome {
        .review(
            DictationReview(
                text: notice == nil ? text : "send it", original: "send it", language: "en-US", style: style,
                notice: notice), engine: .whisper)
    }

    @Test func aRewriteIsShownWithItsOriginalAndStyleAndNothingIsDelivered() async {
        defer { cleanUp() }
        processor.script([rewritten()])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        #expect(coordinator.attention == .reviewRewrite(nil))
        #expect(coordinator.reviewText == "Hi,\n\nPlease send it.\n\nThanks,")
        #expect(coordinator.reviewOriginal == "send it")
        #expect(coordinator.reviewStyle == style)
        #expect(coordinator.attentionActions == [.insertText, .useOriginal, .regenerate, .copyText, .discard])
        #expect(processor.deliveries.isEmpty && copier.copied.isEmpty)
    }

    @Test func insertDeliversTheRewriteOnceAndClearsEverything() async {
        defer { cleanUp() }
        processor.script([rewritten()])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.perform(.insertText)
        await coordinator.settle()

        #expect(processor.deliveries == ["Hi,\n\nPlease send it.\n\nThanks,"])
        #expect(coordinator.state == .completed)
        #expect(coordinator.reviewText == nil && coordinator.reviewOriginal == nil && coordinator.reviewStyle == nil)
        #expect(leftoverFiles.isEmpty)
    }

    @Test func useOriginalDeliversTheTextFromBeforeTheRewrite() async {
        defer { cleanUp() }
        processor.script([rewritten()])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.perform(.useOriginal)
        await coordinator.settle()

        #expect(processor.deliveries == ["send it"])
        #expect(coordinator.state == .completed)
    }

    @Test func copyCopiesWhatTheReviewIsShowing() async {
        defer { cleanUp() }
        processor.script([rewritten()])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        coordinator.toggleReviewOriginal()
        #expect(coordinator.reviewShowsOriginal)

        coordinator.perform(.copyText)
        await coordinator.settle()

        #expect(copier.copied == ["send it"])
        #expect(processor.deliveries.isEmpty, "Copy never inserts")
    }

    @Test func copyCopiesTheRewriteByDefault() async {
        defer { cleanUp() }
        processor.script([rewritten()])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        coordinator.perform(.copyText)
        await coordinator.settle()
        #expect(copier.copied == ["Hi,\n\nPlease send it.\n\nThanks,"])
    }

    @Test func regenerateRewritesTheSameOriginalAndKeepsTheRecording() async {
        defer { cleanUp() }
        processor.script([rewritten(), rewritten("Hello,\n\nKindly send it.\n\nThanks,")])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.perform(.regenerate)
        await coordinator.settle()

        #expect(processor.regenerations == ["send it"])
        #expect(processor.consumed.count == 1, "the audio is not recognised again")
        #expect(coordinator.reviewText == "Hello,\n\nKindly send it.\n\nThanks,")
        #expect(coordinator.reviewOriginal == "send it")
        #expect(!coordinator.reviewShowsOriginal)
        #expect(!leftoverFiles.isEmpty)
    }

    @Test func discardRemovesTheRecordingTheOriginalAndTheRewrite() async {
        defer { cleanUp() }
        processor.script([rewritten()])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.perform(.discard)
        await coordinator.settle()

        #expect(coordinator.state == .idle)
        #expect(coordinator.reviewText == nil && coordinator.reviewOriginal == nil)
        #expect(leftoverFiles.isEmpty)
        #expect(processor.deliveries.isEmpty && copier.copied.isEmpty)
    }

    @Test func aRewriteThatDidNotApplyShowsTheOriginalWithAReasonAndInsertsIt() async {
        defer { cleanUp() }
        processor.script([rewritten(notice: .unavailable(.notEnabled))])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        #expect(coordinator.attention == .reviewRewrite(.unavailable(.notEnabled)))
        #expect(coordinator.attention?.userMessage.contains("Apple Intelligence is turned off") == true)
        #expect(coordinator.attention?.userMessage.contains("Not rewritten") == true)
        #expect(coordinator.reviewOriginal == nil, "there is nothing to compare when no rewrite applied")
        #expect(coordinator.attentionActions == [.insertText, .copyText, .discard])

        coordinator.perform(.insertText)
        await coordinator.settle()
        #expect(processor.deliveries == ["send it"])
    }

    @Test func aNewSessionReplacesAReviewAndForgetsIt() async {
        defer { cleanUp() }
        processor.script([rewritten()])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()

        #expect(coordinator.reviewText == nil && coordinator.reviewOriginal == nil)
        #expect(leftoverFiles.count == 1)
    }

    @Test func styleChoicesAreNamedForTheUserAndVoiceOver() {
        #expect(
            StyleOptions(tone: .professional, format: .email, length: .concise).summary
                == "Professional · Email · Concise")
        #expect(StyleOptions.none.summary.isEmpty)
        #expect(StyleOptions(length: .concise).summary == "Concise")
        #expect(DictationAction.useOriginal.title(engineName: \.displayName) == "Use Original")
        #expect(DictationAction.regenerate.title(engineName: \.displayName) == "Regenerate")
    }
}
