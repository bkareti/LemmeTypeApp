import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

@MainActor
struct RecordingCoordinatorTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let consumer = RecordingSpy()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingCoordinatorTests-\(UUID().uuidString)", isDirectory: true))

    private func makeCoordinator(
        microphone: PermissionStatus = .granted,
        preferences: FakePreferences = FakePreferences()
    ) -> RecordingCoordinator {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: microphone])),
            consumer: consumer,
            feedback: feedback,
            preferences: preferences,
            finishedDisplay: .milliseconds(50),
            failureDisplay: .milliseconds(50)
        )
    }

    private var leftoverFiles: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
    }

    @Test func fullSessionRecordsHandsOffAndReturnsToIdle() async throws {
        let coordinator = makeCoordinator()
        var ended = 0
        coordinator.onSessionEnded = { ended += 1 }

        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        #expect(coordinator.state == .recording)
        #expect(coordinator.recordingStartedAt != nil)

        source.emitTone(seconds: 0.5)
        coordinator.handle(.stop)
        await coordinator.settle()

        #expect(coordinator.state == .completed)
        #expect(consumer.consumed.count == 1)
        #expect(consumer.targets == ["TextEdit"])
        #expect(ended == 1)
        #expect(leftoverFiles.isEmpty)
        #expect(feedback.announcements == ["Recording started", "Recording stopped"])

        try await Task.sleep(for: .milliseconds(150))
        #expect(coordinator.state == .idle)
    }

    @Test func cancelEndsRecordingDeletesAudioAndAnnounces() async {
        let coordinator = makeCoordinator()
        coordinator.handle(.start(nil))
        await coordinator.settle()
        source.emitTone(seconds: 0.3)

        coordinator.requestCancel()
        await coordinator.settle()

        #expect(coordinator.state == .cancelled)
        #expect(!source.isRunning)
        #expect(leftoverFiles.isEmpty)
        #expect(consumer.consumed.isEmpty)
        #expect(feedback.announcements.last == "Recording cancelled")
    }

    @Test func captureFailureLeavesRecordingStateWithANextAction() async {
        let coordinator = makeCoordinator()
        var ended = 0
        coordinator.onSessionEnded = { ended += 1 }
        coordinator.handle(.start(nil))
        await coordinator.settle()

        source.emit(.deviceLost)
        try? await Task.sleep(for: .milliseconds(20))
        await coordinator.settle()

        #expect(coordinator.state == .failed(.deviceDisconnected))
        #expect(coordinator.recoveryAction == .openAudioSettings)
        #expect(!source.isRunning)
        #expect(ended == 1)
        #expect(feedback.announcements.last?.hasPrefix("Recording failed.") == true)
    }

    @Test func missingPermissionFailsBeforeRecordingAndOffersPermissions() async {
        let coordinator = makeCoordinator(microphone: .denied)
        var opened: [SettingsNavigation.Pane] = []
        coordinator.onOpenSettings = { opened.append($0) }

        coordinator.handle(.start(nil))
        await coordinator.settle()

        #expect(coordinator.state == .failed(.microphonePermissionMissing))
        #expect(coordinator.recoveryAction == .openPermissions)
        coordinator.perform(.openPermissions)
        #expect(opened == [.permissions])
        #expect(coordinator.state == .idle)
    }

    @Test func overlappingStartIsRejected() async {
        let coordinator = makeCoordinator()
        coordinator.handle(.start(nil))
        coordinator.handle(.start(nil))
        await coordinator.settle()

        #expect(coordinator.state == .recording)
        #expect(source.startCount == 1)
        coordinator.requestCancel()
        await coordinator.settle()
    }

    @Test func stopDuringPreparingStopsOnceRecordingStarts() async {
        let coordinator = makeCoordinator()

        coordinator.handle(.start(nil))
        coordinator.handle(.stop)  // push-to-talk released immediately
        await coordinator.settle()

        #expect(coordinator.state == .completed)
        #expect(!source.isRunning)
    }

    @Test func levelsFollowAudioOnlyWhileRecording() async throws {
        let coordinator = makeCoordinator()
        coordinator.handle(.start(nil))
        await coordinator.settle()

        source.emitTone(seconds: 0.2, amplitude: 0.5)
        try await Task.sleep(for: .milliseconds(50))
        #expect(coordinator.level > 0.5)

        coordinator.handle(.stop)
        await coordinator.settle()
        #expect(coordinator.level == 0)
    }

    @Test func soundsPlayOnlyWhenEnabled() async {
        let quiet = makeCoordinator(preferences: FakePreferences(playsFeedbackSounds: false))
        quiet.handle(.start(nil))
        quiet.handle(.stop)
        await quiet.settle()
        #expect(feedback.sounds == [.start, .stop])  // the feedback object decides; it is asked each time

        let system = SystemRecordingFeedback(preferences: FakePreferences(playsFeedbackSounds: false))
        system.play(.start)  // no sound, no crash
    }

    @Test func dismissIsOnlyAllowedWhenFinished() async {
        let coordinator = makeCoordinator()
        coordinator.handle(.start(nil))
        await coordinator.settle()

        coordinator.dismiss()
        #expect(coordinator.state == .recording)

        coordinator.requestCancel()
        await coordinator.settle()
        coordinator.dismiss()
        #expect(coordinator.state == .idle)
    }

    @Test func nextActivationAfterAFinishedSessionStartsANewOne() async {
        let coordinator = makeCoordinator()
        coordinator.handle(.start(nil))
        coordinator.handle(.cancel)
        await coordinator.settle()
        #expect(coordinator.state == .cancelled)

        coordinator.handle(.start(nil))
        await coordinator.settle()
        #expect(coordinator.state == .recording)
        coordinator.handle(.cancel)
        await coordinator.settle()
    }
}

@MainActor
final class FakeFeedback: RecordingFeedback {
    private(set) var announcements: [String] = []
    private(set) var sounds: [FeedbackSound] = []

    func announce(_ message: String) { announcements.append(message) }
    func play(_ sound: FeedbackSound) { sounds.append(sound) }
}

/// Records what it was given, then deletes the file like a real consumer.
final class RecordingSpy: RecordingConsumer, @unchecked Sendable {
    // Only mutated from the coordinator's main-actor session.
    private(set) var consumed: [RecordedAudio] = []
    private(set) var targets: [String?] = []

    func consume(_ recording: RecordedAudio, target: ActivationTarget?) async throws(AudioCaptureError) {
        consumed.append(recording)
        targets.append(target?.applicationName)
        try? FileManager.default.removeItem(at: recording.fileURL)
    }
}
