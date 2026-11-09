import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E12-S1: the screen says so whenever a session's audio goes to the cloud, and only then.
@MainActor
struct CloudSpeechIndicatorTests {
    private let source = FakeAudioSource()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-CloudIndicator-\(UUID().uuidString)", isDirectory: true))

    private func makeCoordinator(engine: RecognitionEngineID?) -> RecordingCoordinator {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage,
                permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: RecordingSpy(), feedback: FakeFeedback(),
            preferences: FakePreferences(selectedEngine: engine), textCopier: FakeTextDelivery(),
            finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
    }

    @Test(arguments: [
        (RecognitionEngineID?.some(.cloud), true),
        (.some(.whisper), false),
        (nil, false),
    ])
    func theIndicatorFollowsTheSessionsEngine(engine: RecognitionEngineID?, expected: Bool) async {
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        let coordinator = makeCoordinator(engine: engine)
        #expect(!coordinator.isUsingCloudSpeech, "nothing is showing before a session")
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        #expect(coordinator.isUsingCloudSpeech == expected)
        coordinator.handle(.cancel)
        await coordinator.settle()
    }
}
