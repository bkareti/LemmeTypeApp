import Domain
import Foundation
import Support
import Synchronization
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// Epic 5 end to end (E5-S7): recorder → real pipeline and residency with a
/// manual clock → fake engine. Models load only for dictation, warm up while
/// the user speaks, unload after the idle period or under memory pressure,
/// and never in the middle of a session.
@MainActor
@Suite(.serialized)
struct PerformanceEndToEndTests {
    final class ProfileBox: Sendable {
        private let storage: Mutex<(PerformanceProfile, SystemConditions)>
        init() { storage = Mutex((.balanced, .nominal)) }
        var value: (PerformanceProfile, SystemConditions) {
            get { storage.withLock { $0 } }
            set { storage.withLock { $0 = newValue } }
        }
    }

    @MainActor
    final class Harness {
        let source = FakeAudioSource()
        let clock = ManualClock()
        let engine: FakeRecognitionEngine
        let residency: ModelResidencyController
        let coordinator: RecordingCoordinator
        let delivery = FakeTextDelivery()
        let diagnostics = DiagnosticsBuffer()
        let profile = ProfileBox()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-PerformanceEndToEnd-\(UUID().uuidString)", isDirectory: true)

        init(freeSpace: Int64? = nil) {
            engine = FakeRecognitionEngine(id: .whisper, script: .init(text: "ship it", delay: .milliseconds(20)))
            let profile = self.profile
            residency = ModelResidencyController(
                engines: [engine],
                plan: {
                    let (chosen, conditions) = profile.value
                    return PerformancePlan.make(profile: chosen, conditions: conditions, idleUnload: .default)
                },
                clock: clock, diagnostics: diagnostics)
            coordinator = RecordingCoordinator(
                capture: AudioCaptureService(
                    source: source, storage: AudioSessionStorage(directory: directory),
                    permissions: FakePermissions(statuses: [.microphone: .granted]), freeSpace: { _ in freeSpace }),
                processor: TranscriptionPipeline(engines: [engine], delivery: delivery, diagnostics: diagnostics),
                feedback: SilentFeedback(), preferences: FakePreferences(),
                finishedDisplay: .seconds(60), failureDisplay: .seconds(60), residency: residency,
                diagnostics: diagnostics)
        }

        func dictate(whileRecording: () async -> Void = {}) async {
            coordinator.handle(.start(FakeTargetCapturer.textEdit))
            await coordinator.settle()
            await coordinator.settleResidency()
            await residency.settle()
            await whileRecording()
            source.emitTone(seconds: 0.3)
            coordinator.handle(.stop)
            await coordinator.settle()
            await coordinator.settleResidency()
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func modelsLoadOnlyForDictationAndWarmUpWhileRecording() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        #expect(harness.engine.prepareCount == 0)  // nothing at launch
        await harness.dictate()
        #expect(harness.engine.prepareCount == 1)
        #expect(harness.delivery.delivered == ["ship it"])
    }

    @Test func idlePeriodUnloadsAfterTheLastSession() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        await harness.dictate()
        await harness.clock.waitForSleepers()
        harness.clock.advance(by: .seconds(299))
        #expect(harness.engine.unloadCount == 0)
        harness.clock.advance(by: .seconds(1))
        for _ in 0..<10_000 where harness.engine.unloadCount == 0 { await Task.yield() }
        #expect(harness.engine.unloadCount == 1)
        #expect(String(describing: harness.diagnostics.snapshot()).contains("idle"))
    }

    @Test func memoryPressureMidSessionWaitsAndThenUnloads() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        await harness.dictate { await harness.residency.memoryPressure() }
        #expect(harness.delivery.delivered == ["ship it"])  // recognition kept its model
        #expect(harness.engine.unloadCount == 1)
    }

    @Test func heatSwitchesNewSessionsToLowPower() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.profile.value = (.bestAccuracy, SystemConditions(thermal: .serious))
        await harness.dictate()
        #expect(harness.engine.prepareCount == 0)  // Low Power never warms up
        #expect(harness.delivery.delivered == ["ship it"])
    }

    @Test func lowDiskSpaceRefusesToRecord() async {
        let harness = Harness(freeSpace: 1_000_000)
        defer { harness.cleanUp() }
        harness.coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await harness.coordinator.settle()
        #expect(harness.coordinator.state == .failed(.insufficientStorage))
        #expect(harness.engine.prepareCount == 0)
    }
}
