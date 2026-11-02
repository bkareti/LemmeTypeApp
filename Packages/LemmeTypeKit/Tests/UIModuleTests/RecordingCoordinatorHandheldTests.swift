import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E8-S4: a recording on iPhone or iPad is bounded and ends when the app does.
@MainActor
struct RecordingCoordinatorHandheldTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let processor = RecordingSpy()
    /// The time limit runs on this clock, so no test waits on real time.
    private let clock = ManualClock()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-HandheldCoordinator-\(UUID().uuidString)", isDirectory: true))

    private func makeCoordinator(limits: RecordingLimits = .none) -> RecordingCoordinator {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor,
            feedback: feedback,
            preferences: FakePreferences(),
            finishedDisplay: .milliseconds(50),
            failureDisplay: .milliseconds(50),
            limits: limits,
            limitClock: clock
        )
    }

    private var leftoverFiles: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
    }

    @Test func recordingStopsAndIsProcessedWhenTheTimeLimitIsReached() async {
        let coordinator = makeCoordinator(limits: RecordingLimits(maximumDuration: .seconds(300)))
        coordinator.handle(.start(nil))
        await coordinator.settle()
        #expect(coordinator.state == .recording)
        source.emitTone(seconds: 0.3)
        await clock.waitForSleepers()
        let timer = coordinator.limitTask

        clock.advance(by: .seconds(299))
        #expect(coordinator.state == .recording)
        clock.advance(by: .seconds(1))
        await timer?.value
        await coordinator.settle()

        #expect(!source.isRunning)
        #expect(processor.consumed.count == 1)
        #expect(feedback.announcements.contains("Recording stopped: time limit reached"))
    }

    @Test func noLimitMeansTheRecordingKeepsRunning() async {
        let coordinator = makeCoordinator()
        coordinator.handle(.start(nil))
        await coordinator.settle()

        #expect(coordinator.limitTask == nil)
        #expect(clock.sleeperCount == 0)
        #expect(coordinator.state == .recording)
        #expect(source.isRunning)
        coordinator.requestCancel()
        await coordinator.settle()
    }

    @Test func stoppingBeforeTheLimitDoesNotStopAgain() async {
        let coordinator = makeCoordinator(limits: RecordingLimits(maximumDuration: .seconds(300)))
        coordinator.handle(.start(nil))
        await coordinator.settle()
        await clock.waitForSleepers()
        let timer = coordinator.limitTask
        source.emitTone(seconds: 0.2)
        coordinator.requestStop()
        await coordinator.settle()

        #expect(clock.sleeperCount == 0)  // stopping cancelled the timer
        clock.advance(by: .seconds(600))
        await timer?.value
        await coordinator.settle()

        #expect(processor.consumed.count == 1)
        #expect(!feedback.announcements.contains("Recording stopped: time limit reached"))
    }

    @Test func leavingTheForegroundWhileRecordingStopsAndProcessesWhatWasCaptured() async {
        let coordinator = makeCoordinator()
        coordinator.handle(.start(nil))
        await coordinator.settle()
        source.emitTone(seconds: 0.3)

        coordinator.stopForSystemReason()
        await coordinator.settle()

        #expect(!source.isRunning)
        #expect(processor.consumed.count == 1)
    }

    @Test func leavingTheForegroundWhileIdleDoesNothing() async {
        let coordinator = makeCoordinator()

        coordinator.stopForSystemReason()
        await coordinator.settle()

        #expect(coordinator.state == .idle)
        #expect(processor.consumed.isEmpty)
        #expect(leftoverFiles.isEmpty)
    }
}
