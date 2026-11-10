import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Audio
@testable import UI

private final class HandoffSpy: KeyboardHandoffPublishing {
    private let state = Mutex<(published: [KeyboardHandoff], cleared: Int)>(([], 0))
    var published: [KeyboardHandoff] { state.withLock { $0.published } }
    var cleared: Int { state.withLock { $0.cleared } }
    func publish(_ handoff: KeyboardHandoff) { state.withLock { $0.published.append(handoff) } }
    func clear() { state.withLock { $0.cleared += 1 } }
}

@MainActor
private final class PresenterSpy: ActionDictationPresenting {
    struct Refused: Error {}
    var refuses = false
    var began = 0
    var shown: [ActionDictationStatus] = []
    var ended = 0
    var onBegin: () -> Void = {}

    func begin() throws {
        if refuses { throw Refused() }
        began += 1
        onBegin()
    }
    func show(_ status: ActionDictationStatus) async { shown.append(status) }
    func end() async { ended += 1 }
}

@MainActor
private final class BackgroundTimeSpy: BackgroundTimeRequesting {
    var begun = 0
    var ended = 0
    var expire: (@MainActor () -> Void)?
    func begin(onExpire: @escaping @MainActor () -> Void) {
        begun += 1
        expire = onExpire
    }
    func end() { ended += 1 }
}

/// ADR 0032: the Action Button runs the normal recorder and hands the text to the keyboard.
@MainActor
final class ActionDictationControllerTests {
    private let source = FakeAudioSource()
    private let processor = RecordingSpy()
    private let handoff = HandoffSpy()
    private let presenter = PresenterSpy()
    private let backgroundTime = BackgroundTimeSpy()
    private let gate = BackgroundDictationGate()
    private nonisolated let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-ActionDictation-\(UUID().uuidString)", isDirectory: true)
    private var storage: AudioSessionStorage { AudioSessionStorage(directory: directory) }

    // A failed dictation deliberately keeps its recording for a retry.
    deinit { try? FileManager.default.removeItem(at: directory) }

    private var recordings: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    private static let review = DictationOutcome.needsAttention(
        .reviewTranslation, engine: nil, alternatives: [], transcript: "English text")

    private func makeRecorder() -> RecordingCoordinator {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: FakeFeedback(), preferences: FakePreferences(),
            finishedDisplay: .milliseconds(50), failureDisplay: .seconds(60), attentionDisplay: .seconds(60))
    }

    private func makeController(
        _ recorder: RecordingCoordinator, retention: Duration = .seconds(60),
        prepare: @escaping @MainActor () async -> Void = {}
    ) -> ActionDictationController {
        ActionDictationController(
            recorder: recorder, handoff: handoff, presenter: presenter, backgroundTime: backgroundTime, gate: gate,
            prepare: prepare, pollInterval: .milliseconds(2), resultRetention: retention, failureDisplay: .seconds(60))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func finishedText() -> String? { handoff.published.last(where: { $0.phase == .ready })?.text }

    @Test func thePressStartsAfterTheLiveActivityAndStartupWork() async {
        let recorder = makeRecorder()
        var order: [String] = []
        presenter.onBegin = { order.append("activity") }
        let controller = makeController(recorder) { order.append("startup") }

        await controller.toggle()

        #expect(order == ["startup", "activity"])
        #expect(recorder.state == .recording)
        #expect(source.isRunning)
        #expect(controller.isActive)
        #expect(gate.isActive)
        #expect(handoff.published.last?.phase == .listening)
        recorder.requestCancel()
        await recorder.settle()
    }

    @Test func theSecondPressStopsTheMicAndHandsOverTheText() async {
        processor.script([Self.review])
        let recorder = makeRecorder()
        let controller = makeController(recorder)
        await controller.toggle()
        source.emitTone(seconds: 0.2)

        await controller.toggle()
        await waitUntil { finishedText() != nil }

        #expect(!source.isRunning)
        #expect(finishedText() == "English text")
        #expect(handoff.published.contains { $0.phase == .writing })
        #expect(presenter.shown == [.writing])
        #expect(presenter.ended >= 2)
        #expect(backgroundTime.begun >= 1)
        #expect(!controller.isActive)
        #expect(!gate.isActive)
    }

    @Test func theTextStaysInTheReviewSoItIsNotLost() async {
        processor.script([Self.review])
        let recorder = makeRecorder()
        let controller = makeController(recorder)
        await controller.toggle()
        source.emitTone(seconds: 0.2)
        await controller.toggle()
        await waitUntil { finishedText() != nil }

        #expect(recorder.reviewText == "English text")
    }

    @Test func theRecordingIsDeletedOnceTheTextIsHandedOver() async {
        processor.script([Self.review])
        let recorder = makeRecorder()
        let controller = makeController(recorder)
        await controller.toggle()
        source.emitTone(seconds: 0.2)
        await controller.toggle()
        await waitUntil { finishedText() != nil }

        #expect(recordings.isEmpty)
        #expect(!recorder.attentionActions.contains(.retry))
    }

    @Test func aResultIsErasedAfterItsRetention() async {
        processor.script([Self.review])
        let recorder = makeRecorder()
        let controller = makeController(recorder, retention: .milliseconds(5))
        await controller.toggle()
        source.emitTone(seconds: 0.2)
        let clearedBefore = handoff.cleared

        await controller.toggle()
        await waitUntil { handoff.cleared > clearedBefore && backgroundTime.ended >= 2 }

        #expect(handoff.cleared > clearedBefore)
        #expect(backgroundTime.ended >= 2)
    }

    @Test func runningOutOfBackgroundTimeErasesTheResult() async {
        processor.script([Self.review])
        let recorder = makeRecorder()
        let controller = makeController(recorder)
        await controller.toggle()
        source.emitTone(seconds: 0.2)
        await controller.toggle()
        await waitUntil { finishedText() != nil }
        let clearedBefore = handoff.cleared

        backgroundTime.expire?()

        #expect(handoff.cleared == clearedBefore + 1)
    }

    @Test func aPressWhileWritingIsIgnored() async {
        processor.script([Self.review], delay: .milliseconds(100))
        let recorder = makeRecorder()
        let controller = makeController(recorder)
        await controller.toggle()
        source.emitTone(seconds: 0.2)
        await controller.toggle()
        await waitUntil { recorder.state == .processing }

        await controller.toggle()

        #expect(!source.isRunning)
        #expect(presenter.began == 1)
        await waitUntil { finishedText() != nil }
    }

    @Test func aRefusedLiveActivityMeansNoRecording() async {
        presenter.refuses = true
        let recorder = makeRecorder()
        let controller = makeController(recorder)

        await controller.toggle()

        #expect(recorder.state == .idle)
        #expect(!source.isRunning)
        #expect(!controller.isActive)
        #expect(handoff.published.last?.phase == .failed)
    }

    @Test func aFailedDictationReportsWithoutAnyText() async {
        processor.script([
            .needsAttention(.recognitionFailed(.noSpeechDetected), engine: nil, alternatives: [], transcript: nil)
        ])
        let recorder = makeRecorder()
        let controller = makeController(recorder)
        await controller.toggle()
        source.emitTone(seconds: 0.2)

        await controller.toggle()
        await waitUntil { handoff.published.last?.phase == .failed }

        #expect(handoff.published.last?.text == nil)
        #expect(presenter.shown.last == .failed)
        #expect(!gate.isActive)
    }

    @Test func aRecordingStartedOnScreenIsStoppedWithoutTheBackgroundPath() async {
        let recorder = makeRecorder()
        let controller = makeController(recorder)
        recorder.requestStart(target: nil)
        await recorder.settle()
        source.emitTone(seconds: 0.2)

        await controller.toggle()
        await recorder.settle()

        #expect(!source.isRunning)
        #expect(presenter.began == 0)
        #expect(backgroundTime.begun == 0)
    }

    @Test func aRecordingEndingOnItsOwnStillDeliversTheText() async {
        processor.script([Self.review])
        let recorder = makeRecorder()
        let controller = makeController(recorder)
        await controller.toggle()
        source.emitTone(seconds: 0.2)

        recorder.requestStop()
        await waitUntil { finishedText() != nil }

        #expect(finishedText() == "English text")
        #expect(backgroundTime.begun >= 1)
    }
}
