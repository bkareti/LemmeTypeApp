import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Recognition

/// E8-S5: a phone refuses to load a model it has no room for.
struct WhisperEngineMemoryTests {
    private let fixtures = RecordingFixtures()
    private static let iPhone8GB = HardwareProfile(
        isAppleSilicon: true, physicalMemoryBytes: 7_800_000_000, deviceClass: .iPhone)

    private func makeEngine(available: UInt64?, runtime: FakeWhisperRuntime) -> WhisperEngine {
        WhisperEngine(
            assets: FakeModelAssetManager(installed: [.whisperBaseEnglish]), hardware: Self.iPhone8GB,
            runtime: runtime, availableMemory: { available })
    }

    @Test func tooLittleAvailableMemoryRefusesTheLoadAndLoadsNothing() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime()
        let engine = makeEngine(available: 300_000_000, runtime: runtime)  // Base needs 388 MB + margin

        #expect(await engine.availability() == .unsupported(.insufficientMemory))
        await #expect(throws: RecognitionError.unsupported(.insufficientMemory)) {
            try await RecognitionRunner().run(engine, try fixtures.make(.tone(seconds: 1.5))) { _ in }
        }
        #expect(runtime.loadCount == 0)
    }

    @Test func enoughAvailableMemoryLoadsAndTranscribes() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime()
        let engine = makeEngine(available: 2_000_000_000, runtime: runtime)

        let transcript = try await RecognitionRunner().run(engine, try fixtures.make(.tone(seconds: 1.5))) { _ in }

        #expect(!transcript.text.isEmpty)
        #expect(runtime.loadCount == 1)
    }

    @Test func aLoadedModelIsNotRefusedWhenMemoryLaterRunsLow() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime()
        let available = Mutex<UInt64>(2_000_000_000)
        let engine = WhisperEngine(
            assets: FakeModelAssetManager(installed: [.whisperBaseEnglish]), hardware: Self.iPhone8GB,
            runtime: runtime, availableMemory: { available.withLock { $0 } })
        try await engine.prepare()

        available.withLock { $0 = 100_000_000 }  // loading the model used most of it

        #expect(await engine.availability() == .ready)
    }

    @Test func theMacIsNeverMemoryLimited() async {
        let engine = WhisperEngine(
            assets: FakeModelAssetManager(installed: [.whisperBaseEnglish]),
            hardware: HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 16 << 30),
            runtime: FakeWhisperRuntime())

        #expect(await engine.availability() == .ready)
    }
}
