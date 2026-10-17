import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E5-S4/E5-S6: the recorder tells residency when a session is busy, so models
/// warm up while the user speaks and are never unloaded mid-session; and
/// recording refuses to start without disk space.
@MainActor
struct RecordingResidencyTests {
    final class ResidencySpy: ModelResidencyManaging {
        private let log = Mutex<[String]>([])
        var calls: [String] { log.withLock { $0 } }

        func sessionBusy() async { log.withLock { $0.append("busy") } }
        func warmUp(preferred: RecognitionEngineID?, language: String) async {
            log.withLock { $0.append("warm-up:\(preferred?.rawValue ?? "automatic"):\(language)") }
        }
        func sessionIdle() async { log.withLock { $0.append("idle") } }
        func memoryPressure() async { log.withLock { $0.append("memory") } }
    }

    private func makeCoordinator(
        residency: ResidencySpy, processor: RecordingSpy = RecordingSpy(), freeSpace: Int64? = nil,
        source: FakeAudioSource
    ) -> RecordingCoordinator {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source,
                storage: AudioSessionStorage(
                    directory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("LemmeTypeTests-Residency-\(UUID().uuidString)")),
                permissions: FakePermissions(statuses: [.microphone: .granted]),
                freeSpace: { _ in freeSpace }),
            processor: processor, feedback: FakeFeedback(), preferences: FakePreferences(selectedEngine: .whisper),
            finishedDisplay: .milliseconds(10), failureDisplay: .milliseconds(10), residency: residency)
    }

    @Test func aSessionIsBusyFromRecordingUntilItFinishes() async {
        let residency = ResidencySpy()
        let source = FakeAudioSource()
        let coordinator = makeCoordinator(residency: residency, source: source)

        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        await coordinator.settleResidency()
        #expect(residency.calls == ["busy", "warm-up:whisper:en-US"])

        source.emitTone(seconds: 0.3)
        coordinator.handle(.stop)
        await coordinator.settle()
        await coordinator.settleResidency()
        #expect(residency.calls == ["busy", "warm-up:whisper:en-US", "busy", "idle"])
    }

    @Test func cancellingEndsTheBusyPeriod() async {
        let residency = ResidencySpy()
        let coordinator = makeCoordinator(residency: residency, source: FakeAudioSource())
        coordinator.handle(.start(nil))
        await coordinator.settle()
        coordinator.handle(.cancel)
        await coordinator.settle()
        await coordinator.settleResidency()
        #expect(residency.calls.last == "idle")
    }

    @Test func lowDiskSpaceStopsRecordingBeforeItStarts() async {
        let residency = ResidencySpy()
        let source = FakeAudioSource()
        let coordinator = makeCoordinator(residency: residency, freeSpace: 10_000_000, source: source)
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        #expect(coordinator.state == .failed(.insufficientStorage))
        #expect(coordinator.failure?.userMessage.hasPrefix("Not enough disk space to record") == true)
        #expect(!residency.calls.contains("busy"))
    }
}
