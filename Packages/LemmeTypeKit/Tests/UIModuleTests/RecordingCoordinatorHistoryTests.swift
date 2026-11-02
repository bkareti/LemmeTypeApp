import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E6-S3: text the user copies from a review is offered to the history; text the
/// pipeline delivers is offered by the pipeline (tested in `DictationHistoryPipelineTests`).
@MainActor
struct RecordingCoordinatorHistoryTests {
    private let source = FakeAudioSource()
    private let processor = RecordingSpy()
    private let copier = FakeTextDelivery()
    private let history = FakeDictationHistoryRecorder()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-CoordinatorHistory-\(UUID().uuidString)", isDirectory: true))

    private func makeCoordinator() -> RecordingCoordinator {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage,
                permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: FakeFeedback(), preferences: FakePreferences(), textCopier: copier,
            history: history, finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }

    private func speak(_ coordinator: RecordingCoordinator) async {
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        source.emitTone(seconds: 0.5)
        coordinator.handle(.stop)
        await coordinator.settle()
    }

    private func review() -> DictationOutcome {
        .review(
            DictationReview(
                text: "Hi,\n\nPlease send it.", original: "send it", language: "en-US",
                style: StyleOptions(tone: .professional, format: .email), notice: nil), engine: .whisper)
    }

    @Test func copyingTheReviewedRewriteOffersItToTheHistory() async {
        defer { cleanUp() }
        processor.script([review()])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.perform(.copyText)
        await coordinator.settle()

        #expect(history.calls.map(\.text) == ["Hi,\n\nPlease send it."])
        #expect(history.calls.map(\.delivery) == [.copied])
    }

    @Test func copyingTheOriginalOffersTheOriginal() async {
        defer { cleanUp() }
        processor.script([review()])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        coordinator.toggleReviewOriginal()

        coordinator.perform(.copyText)
        await coordinator.settle()

        #expect(history.calls.map(\.text) == ["send it"])
    }

    @Test func discardingOffersNothing() async {
        defer { cleanUp() }
        processor.script([review()])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.perform(.discard)
        await coordinator.settle()

        #expect(history.calls.isEmpty)
    }
}
