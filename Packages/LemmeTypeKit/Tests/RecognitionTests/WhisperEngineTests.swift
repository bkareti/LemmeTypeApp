import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Recognition

/// Stand-in for whisper.cpp: counts loads and live models, and can block
/// inference until aborted.
final class FakeWhisperRuntime: WhisperRuntime {
    private let state = Mutex((loads: 0, live: 0))
    let segments: [TranscriptSegment]
    let loadDelay: Duration
    let inferenceBlocksUntilAborted: Bool

    init(
        segments: [TranscriptSegment] = [
            TranscriptSegment(text: "Ship it", start: 0, duration: 0.6),
            TranscriptSegment(text: " on Wednesday.", start: 0.6, duration: 0.8),
        ],
        loadDelay: Duration = .zero,
        inferenceBlocksUntilAborted: Bool = false
    ) {
        self.segments = segments
        self.loadDelay = loadDelay
        self.inferenceBlocksUntilAborted = inferenceBlocksUntilAborted
    }

    var loadCount: Int { state.withLock { $0.loads } }
    var liveModels: Int { state.withLock { $0.live } }

    func loadModel(at url: URL) throws(RecognitionError) -> any WhisperModel {
        if loadDelay > .zero {
            Thread.sleep(
                forTimeInterval: Double(loadDelay.components.seconds)
                    + Double(loadDelay.components.attoseconds) / 1e18)
        }
        state.withLock {
            $0.loads += 1
            $0.live += 1
        }
        return Model(runtime: self)
    }

    fileprivate func released() {
        state.withLock { $0.live -= 1 }
    }

    private let prompts = Mutex<[String?]>([])
    var receivedPrompts: [String?] { prompts.withLock { $0 } }

    fileprivate func recordPrompt(_ prompt: String?) {
        prompts.withLock { $0.append(prompt) }
    }

    final class Model: WhisperModel {
        let runtime: FakeWhisperRuntime

        init(runtime: FakeWhisperRuntime) {
            self.runtime = runtime
        }

        deinit {
            runtime.released()
        }

        func transcribe(
            _ samples: [Float],
            language: String,
            prompt: String?,
            shouldAbort: @escaping @Sendable () -> Bool,
            progress: @escaping @Sendable (Double) -> Void
        ) throws(RecognitionError) -> [TranscriptSegment] {
            runtime.recordPrompt(prompt)
            progress(0.5)
            if runtime.inferenceBlocksUntilAborted {
                while !shouldAbort() {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                throw .cancelled
            }
            progress(1)
            return runtime.segments
        }
    }
}

struct WhisperEngineTests {
    private let fixtures = RecordingFixtures()
    private static let appleSilicon16GB = HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 16 << 30)

    private func makeEngine(
        installed: Bool = true,
        hardware: HardwareProfile = appleSilicon16GB,
        runtime: FakeWhisperRuntime = FakeWhisperRuntime()
    ) -> WhisperEngine {
        WhisperEngine(
            assets: FakeModelAssetManager(installed: installed ? [.whisperBaseEnglish] : []),
            hardware: hardware,
            runtime: runtime
        )
    }

    @Test func installedModelProducesAFinalEnglishTranscriptOffline() async throws {
        defer { fixtures.removeAll() }
        let engine = makeEngine()
        let updates = Mutex<[RecognitionUpdate]>([])

        let transcript = try await RecognitionRunner().run(engine, try fixtures.make(.tone(seconds: 1.5))) { update in
            updates.withLock { $0.append(update) }
        }

        #expect(transcript.text == "Ship it on Wednesday.")
        #expect(transcript.engine == .whisper)
        #expect(transcript.segments.count == 2)
        #expect(transcript.segments.last?.start == 0.6)
        #expect(updates.withLock { $0 }.contains(.progress(1)))
    }

    @Test func vocabularyHintsBecomeABoundedInitialPrompt() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime()
        let engine = makeEngine(runtime: runtime)
        let tone = try fixtures.make(.tone(seconds: 1.5))
        _ = try await engine.recognize(
            RecognitionRequest(audio: tone.audio, language: "en-US", hints: ["LemmeType", " ", "Kubernetes"])
        ) { _ in }
        _ = try await engine.recognize(tone) { _ in }
        #expect(runtime.receivedPrompts == ["Glossary: LemmeType, Kubernetes.", nil])

        let many = (0..<200).map { "Term\($0)" }
        let prompt = try #require(WhisperEngine.prompt(for: many))
        #expect(prompt.count <= WhisperEngine.maximumPromptLength + "Glossary: .".count)
        #expect(WhisperEngine.prompt(for: []) == nil)
    }

    @Test func missingModelIsAssetsMissing() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime()
        let engine = makeEngine(installed: false, runtime: runtime)
        #expect(await engine.availability() == .assetsMissing)
        await #expect(throws: RecognitionError.assetsMissing) {
            try await engine.recognize(try fixtures.make(.tone(seconds: 1))) { _ in }
        }
        #expect(runtime.loadCount == 0)
    }

    @Test(arguments: [
        (HardwareProfile(isAppleSilicon: false, physicalMemoryBytes: 32 << 30), UnsupportedReason.hardware),
        (HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 4 << 30), .insufficientMemory),
    ])
    func unsupportedHardwareIsNotOfferedEvenWithoutTheModel(hardware: HardwareProfile, reason: UnsupportedReason)
        async
    {
        let engine = makeEngine(installed: false, hardware: hardware)
        #expect(await engine.availability() == .unsupported(reason))
    }

    @Test func warmUpLoadsOnceAndUnloadReleasesMemory() async throws {
        let runtime = FakeWhisperRuntime()
        let engine = makeEngine(runtime: runtime)

        try await engine.prepare()
        try await engine.prepare()
        #expect(runtime.loadCount == 1)
        #expect(await engine.isLoaded)

        await engine.unload()
        #expect(await !engine.isLoaded)
        #expect(runtime.liveModels == 0)
    }

    @Test func cancellationDuringWarmUpStopsAndReleasesTheModel() async throws {
        let runtime = FakeWhisperRuntime(loadDelay: .milliseconds(300))
        let engine = makeEngine(runtime: runtime)

        let task = Task { try await engine.prepare() }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        await #expect(throws: RecognitionError.cancelled) { try await task.value }
        #expect(await !engine.isLoaded)
        try await Task.sleep(for: .milliseconds(500))
        #expect(runtime.liveModels == 0)
    }

    @Test func cancellationDuringInferenceStopsPromptly() async throws {
        defer { fixtures.removeAll() }
        let engine = makeEngine(runtime: FakeWhisperRuntime(inferenceBlocksUntilAborted: true))
        let request = try fixtures.make(.tone(seconds: 1))
        let start = ContinuousClock.now

        let task = Task { try await RecognitionRunner().run(engine, request) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        await #expect(throws: RecognitionError.cancelled) { try await task.value }
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func silenceNeverReachesTheModel() async throws {
        defer { fixtures.removeAll() }
        let engine = makeEngine()
        await #expect(throws: RecognitionError.noSpeechDetected) {
            try await engine.recognize(try fixtures.make(.silence(seconds: 1))) { _ in }
        }
    }

    @Test func blankModelOutputIsNoSpeech() async throws {
        defer { fixtures.removeAll() }
        let engine = makeEngine(runtime: FakeWhisperRuntime(segments: []))
        await #expect(throws: RecognitionError.noSpeechDetected) {
            try await engine.recognize(try fixtures.make(.tone(seconds: 1))) { _ in }
        }
    }

    @Test(arguments: [true, false])
    func satisfiesTheEngineContract(installed: Bool) async throws {
        defer { fixtures.removeAll() }
        let engine = makeEngine(installed: installed)
        let issues = await RecognitionEngineContract.verify(engine, request: try fixtures.make(.tone(seconds: 1)))
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test func realRuntimeRejectsAMissingModelFile() {
        #expect(throws: RecognitionError.modelLoadFailed) {
            _ = try WhisperCppRuntime().loadModel(at: URL(fileURLWithPath: "/nonexistent/ggml-base.en.bin"))
        }
    }
}
