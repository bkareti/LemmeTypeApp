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
            limits: limits
        )
    }

    private var leftoverFiles: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
    }

    @Test func recordingStopsAndIsProcessedWhenTheTimeLimitIsReached() async throws {
        let coordinator = makeCoordinator(limits: RecordingLimits(maximumDuration: .milliseconds(80)))
        coordinator.handle(.start(nil))
        await coordinator.settle()
        #expect(coordinator.state == .recording)
        source.emitTone(seconds: 0.3)

        try await Task.sleep(for: .milliseconds(250))
        await coordinator.settle()

        #expect(!source.isRunning)
        #expect(processor.consumed.count == 1)
        #expect(feedback.announcements.contains("Recording stopped: time limit reached"))
    }

    @Test func noLimitMeansTheRecordingKeepsRunning() async throws {
        let coordinator = makeCoordinator()
        coordinator.handle(.start(nil))
        await coordinator.settle()

        try await Task.sleep(for: .milliseconds(150))

        #expect(coordinator.state == .recording)
        #expect(source.isRunning)
        coordinator.requestCancel()
        await coordinator.settle()
    }

    @Test func stoppingBeforeTheLimitDoesNotStopAgain() async throws {
        let coordinator = makeCoordinator(limits: RecordingLimits(maximumDuration: .milliseconds(150)))
        coordinator.handle(.start(nil))
        await coordinator.settle()
        source.emitTone(seconds: 0.2)
        coordinator.requestStop()
        await coordinator.settle()

        try await Task.sleep(for: .milliseconds(250))
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
