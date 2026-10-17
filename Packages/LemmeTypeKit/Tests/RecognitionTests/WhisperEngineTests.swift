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

    private let loads = Mutex<[(url: URL, usesGPU: Bool)]>([])
    /// The file and GPU setting of every load, in order.
    var loadedFiles: [String] { loads.withLock { $0.map(\.url.lastPathComponent) } }
    var loadedWithGPU: [Bool] { loads.withLock { $0.map(\.usesGPU) } }
    fileprivate let threads = Mutex<[Int]>([])
    var inferenceThreads: [Int] { threads.withLock { $0 } }

    func loadModel(at url: URL, usesGPU: Bool) throws(RecognitionError) -> any WhisperModel {
        loads.withLock { $0.append((url, usesGPU)) }
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
            _ inference: WhisperInference,
            shouldAbort: @escaping @Sendable () -> Bool,
            progress: @escaping @Sendable (Double) -> Void
        ) throws(RecognitionError) -> [TranscriptSegment] {
            runtime.recordPrompt(inference.prompt)
            runtime.threads.withLock { $0.append(inference.threads) }
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

    // MARK: E5-S1, E5-S3, E5-S5 — model choice, verification, plan

    private func makeEngine(
        installed: Set<ModelAssetID>, settings: WhisperRunSettings, runtime: FakeWhisperRuntime = FakeWhisperRuntime(),
        assets: FakeModelAssetManager? = nil
    ) -> WhisperEngine {
        let box = SettingsBox(settings)
        return WhisperEngine(
            assets: assets ?? FakeModelAssetManager(installed: installed), hardware: Self.appleSilicon16GB,
            runtime: runtime, settings: { box.value })
    }

    @Test func existingBaseInstallKeepsWorkingWithDefaults() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime()
        let engine = makeEngine(installed: [.whisperBaseEnglish], settings: WhisperRunSettings(), runtime: runtime)
        #expect(await engine.availability() == .ready)
        _ = try await engine.recognize(try fixtures.make(.tone(seconds: 1.5))) { _ in }
        #expect(runtime.loadedFiles == ["ggml-base.en.bin"])
    }

    @Test func automaticRunsTheFirstInstalledModelInThePlanOrder() async throws {
        let runtime = FakeWhisperRuntime()
        let order: [ModelAssetID] = [.whisperSmallEnglish, .whisperBaseEnglish, .whisperTinyEnglish]
        let engine = makeEngine(
            installed: [.whisperTinyEnglish, .whisperBaseEnglish],
            settings: WhisperRunSettings(choice: .automatic, order: order), runtime: runtime)
        try await engine.prepare()
        #expect(runtime.loadedFiles == ["ggml-base.en.bin"])
    }

    @Test func aChosenModelThatIsNotInstalledIsNeverReplaced() async throws {
        let runtime = FakeWhisperRuntime()
        let engine = makeEngine(
            installed: [.whisperBaseEnglish], settings: WhisperRunSettings(choice: .specific(.whisperSmallEnglish)),
            runtime: runtime)
        #expect(await engine.availability() == .assetsMissing)
        await #expect(throws: RecognitionError.assetsMissing) { try await engine.prepare() }
        #expect(runtime.loadCount == 0)
    }

    @Test func aModifiedModelIsNeverLoaded() async throws {
        let runtime = FakeWhisperRuntime()
        let assets = FakeModelAssetManager(installed: [.whisperBaseEnglish])
        assets.tamper(with: .whisperBaseEnglish)
        let engine = makeEngine(installed: [], settings: WhisperRunSettings(), runtime: runtime, assets: assets)
        await #expect(throws: RecognitionError.assetsMissing) { try await engine.prepare() }
        #expect(runtime.loadCount == 0)
        #expect(await engine.availability() == .assetsMissing)
    }

    @Test func verificationRunsOnlyWhenLoading() async throws {
        let assets = FakeModelAssetManager(installed: [.whisperBaseEnglish])
        let engine = makeEngine(installed: [], settings: WhisperRunSettings(), assets: assets)
        _ = await engine.availability()
        #expect(assets.verifyCount == 0)
        try await engine.prepare()
        try await engine.prepare()  // already loaded: no second check
        #expect(assets.verifyCount == 1)
    }

    @Test func planThreadsAndGPUReachTheRuntimeAndAGPUChangeReloads() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime()
        let box = SettingsBox(WhisperRunSettings(threads: 2, usesGPU: false))
        let engine = WhisperEngine(
            assets: FakeModelAssetManager(installed: [.whisperBaseEnglish]), hardware: Self.appleSilicon16GB,
            runtime: runtime, settings: { box.value })
        _ = try await engine.recognize(try fixtures.make(.tone(seconds: 1.5))) { _ in }
        #expect(runtime.inferenceThreads == [2])
        #expect(runtime.loadedWithGPU == [false])

        box.value = WhisperRunSettings(threads: 6, usesGPU: true)
        _ = try await engine.recognize(try fixtures.make(.tone(seconds: 1.5))) { _ in }
        #expect(runtime.loadedWithGPU == [false, true])
        #expect(runtime.inferenceThreads == [2, 6])
    }

    @Test func modelsThisMacCantRunAreUnsupported() async {
        let engine = WhisperEngine(
            assets: FakeModelAssetManager(),
            hardware: HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 4 << 30),
            runtime: FakeWhisperRuntime())
        #expect(await engine.availability() == .unsupported(.insufficientMemory))
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
            _ = try WhisperCppRuntime().loadModel(
                at: URL(fileURLWithPath: "/nonexistent/ggml-base.en.bin"), usesGPU: false)
        }
    }
}

/// Settings the test can change between sessions.
final class SettingsBox: Sendable {
    private let storage: Mutex<WhisperRunSettings>

    init(_ value: WhisperRunSettings) {
        storage = Mutex(value)
    }

    var value: WhisperRunSettings {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
