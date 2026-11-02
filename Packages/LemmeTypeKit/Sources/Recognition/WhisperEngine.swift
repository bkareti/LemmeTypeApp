import Domain
import Foundation
import Support

/// How the Whisper engine runs for the next session (E5-S1, E5-S5): which
/// model, and the performance plan's threads and GPU use.
public struct WhisperRunSettings: Equatable, Sendable {
    public var choice: WhisperModelChoice
    /// Model preference for the Automatic choice, first installed wins.
    public var order: [ModelAssetID]
    public var threads: Int
    public var usesGPU: Bool
    /// What warm-up prepares for: the language and output Settings has now
    /// (E9-S2). A request that needs something else loads its own model.
    public var warmUpNeed: RecognitionNeed

    public init(
        choice: WhisperModelChoice = .automatic,
        order: [ModelAssetID] = [.whisperBaseEnglish, .whisperSmallEnglish, .whisperTinyEnglish],
        threads: Int = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)),
        usesGPU: Bool = true,
        warmUpNeed: RecognitionNeed = RecognitionNeed(language: "en")
    ) {
        self.choice = choice
        self.order = order
        self.threads = threads
        self.usesGPU = usesGPU
        self.warmUpNeed = warmUpNeed
    }
}

/// The downloadable Whisper models (whisper.cpp Tiny, Base, Small) behind the
/// engine contract. Runs entirely on this Mac; see
/// docs/decisions/0012-local-whisper-model.md and 0022-model-management.md.
///
/// The model is loaded by ``prepare()`` (warm-up) and kept until ``unload()``.
/// Only a file verified against the catalog in this launch is loaded. Audio
/// samples exist only for the duration of ``recognize(_:updates:)``.
public actor WhisperEngine: SpeechRecognitionEngine {
    public nonisolated let descriptor: EngineDescriptor

    private let models: [ModelAsset]
    private let assets: any ModelAssetManaging
    private let hardware: HardwareProfile
    private let runtime: any WhisperRuntime
    private let settings: @Sendable () -> WhisperRunSettings
    /// Memory the app may still use, on a device that limits it (iPhone and
    /// iPad, E8-S5); `nil` where the system does not (the Mac).
    private let availableMemory: @Sendable () -> UInt64?
    /// Left free beyond the model's own estimate so loading it does not get the app ended.
    static let memoryMargin: UInt64 = 200_000_000
    private var model: (any WhisperModel)?
    private var loaded: (url: URL, usesGPU: Bool)?

    public init(
        assets: any ModelAssetManaging, hardware: HardwareProfile = .current,
        availableMemory: @escaping @Sendable () -> UInt64? = { nil },
        settings: @escaping @Sendable () -> WhisperRunSettings = { WhisperRunSettings() }
    ) {
        self.init(
            assets: assets, hardware: hardware, runtime: WhisperCppRuntime(), settings: settings,
            availableMemory: availableMemory)
    }

    init(
        assets: any ModelAssetManaging,
        hardware: HardwareProfile,
        runtime: any WhisperRuntime,
        models: [ModelAsset] = ModelCatalog.whisperModels,
        settings: @escaping @Sendable () -> WhisperRunSettings = { WhisperRunSettings() },
        availableMemory: @escaping @Sendable () -> UInt64? = { nil }
    ) {
        self.availableMemory = availableMemory
        self.models = models
        self.assets = assets
        self.hardware = hardware
        self.runtime = runtime
        self.settings = settings
        descriptor = EngineDescriptor(
            id: .whisper,
            supportedLanguages: SpokenLanguages.detectionCandidates,
            // The default download offered from Settings › Dictation.
            assets: .downloadable(.whisperBaseEnglish),
            capabilities: [.segmentTimings, .progress, .languageDetection],
            tasks: [.transcribe, .translateToEnglish]
        )
    }

    /// Whether English dictation can run. Hardware is checked before assets,
    /// so an incompatible Mac is never offered the download.
    public func availability() async -> EngineAvailability {
        await availability(for: RecognitionNeed(language: "en"))
    }

    /// Whether `need` can run: an installed model must serve the language and
    /// task (E9-S2).
    public func availability(for need: RecognitionNeed) async -> EngineAvailability {
        guard descriptor.supports(need) else { return .unsupported(.language) }
        switch await resolve(settings(), for: need) {
        case .success(let asset):
            return lacksMemory(for: asset) ? .unsupported(.insufficientMemory) : .ready
        case .failure(.unsupported(let reason)): return .unsupported(reason)
        case .failure: return .assetsMissing
        }
    }

    /// The model this request runs: the specific choice, or the first
    /// installed model in the plan's order that serves it and this Mac
    /// supports. English-only models come first for English; the multilingual
    /// model of the same size follows (E9-S2).
    private func resolve(_ settings: WhisperRunSettings, for need: RecognitionNeed) async -> Result<
        ModelAsset, RecognitionError
    > {
        let candidates: [ModelAsset]
        switch settings.choice {
        case .specific(let id):
            candidates = models.filter { $0.id == id }
        case .automatic:
            let preferred = settings.order.compactMap { id in models.first { $0.id == id } }
            let multilingual = settings.order.compactMap(ModelCatalog.multilingualCounterpart(of:))
                .compactMap { id in models.first { $0.id == id } }
            candidates = preferred + multilingual.filter { model in !preferred.contains { $0.id == model.id } }
        }
        let serving = candidates.filter { $0.serves(language: need.language, task: need.task) }
        // A chosen model that cannot serve the language is a language problem,
        // not a missing download.
        if serving.isEmpty, !candidates.isEmpty { return .failure(.unsupported(.language)) }
        var unsupported: UnsupportedReason?
        for asset in serving {
            if let reason = asset.hardware.unsupportedReason(for: hardware) {
                unsupported = unsupported ?? reason
                continue
            }
            if await modelFile(asset, verified: false) != nil { return .success(asset) }
        }
        let anySupported = serving.contains { $0.hardware.unsupportedReason(for: hardware) == nil }
        if let unsupported, !anySupported { return .failure(.unsupported(unsupported)) }
        return .failure(.assetsMissing)
    }

    /// Whether loading `asset` now would leave too little memory. A model that
    /// is already loaded needs no more.
    private func lacksMemory(for asset: ModelAsset) -> Bool {
        guard model == nil, let available = availableMemory() else { return false }
        return available < asset.runtimeMemoryBytes + Self.memoryMargin
    }

    public func prepare() async throws(RecognitionError) {
        _ = try await load(for: settings().warmUpNeed)
    }

    /// Loads (or keeps) the model that serves `need`.
    @discardableResult
    private func load(for need: RecognitionNeed) async throws(RecognitionError) -> any WhisperModel {
        let settings = settings()
        let asset = try await resolve(settings, for: need).get()
        if model != nil, let loaded, loaded.usesGPU == settings.usesGPU,
            await modelFile(asset, verified: false) == loaded.url, let model
        {
            return model
        }
        guard let url = await modelFile(asset, verified: true) else { throw .assetsMissing }
        model = nil
        loaded = nil
        // Refuse before loading rather than be ended by the system halfway through.
        if lacksMemory(for: asset) { throw .unsupported(.insufficientMemory) }
        let runtime = self.runtime
        let usesGPU = settings.usesGPU
        // Loading cannot be interrupted inside whisper.cpp, so it runs
        // detached: a cancelled warm-up returns at once and the loaded model
        // is released as soon as loading finishes.
        let loading = Task.detached { try runtime.loadModel(at: url, usesGPU: usesGPU) }
        let loaded: any WhisperModel
        do {
            loaded = try await withTaskCancellationHandler {
                try await loading.value
            } onCancel: {
                loading.cancel()
            }
        } catch {
            throw Task.isCancelled ? .cancelled : (error as? RecognitionError ?? .modelLoadFailed)
        }
        if Task.isCancelled { throw .cancelled }
        model = loaded
        self.loaded = (url, usesGPU)
        Log.recognition.info("Whisper model loaded: \(asset.id.rawValue, privacy: .public)")
        return loaded
    }

    public func recognize(
        _ request: RecognitionRequest,
        updates: @escaping @Sendable (RecognitionUpdate) -> Void
    ) async throws(RecognitionError) -> Transcript {
        if Task.isCancelled { throw .cancelled }
        let need = request.need
        if let error = await availability(for: need).recognitionError { throw error }
        guard request.audio.duration >= SpeechActivity.minimumDuration else { throw .noSpeechDetected }
        let model = try await load(for: need)
        let threads = settings().threads

        let start = ContinuousClock.now
        let samples = try AudioFileReader.readSamples(from: request.audio.fileURL)
        guard !samples.isEmpty else { throw .noSpeechDetected }
        guard !SpeechActivity.isSilent(samples) else { throw .silentAudio }
        let language = try await Self.spokenLanguage(
            for: request.language, samples: samples, with: model, threads: threads)
        let inference = WhisperInference(
            language: language, task: request.task, prompt: Self.prompt(for: request.hints), threads: threads)
        let segments = try await Self.transcribe(samples, with: model, inference: inference, updates: updates)
        if Task.isCancelled { throw .cancelled }
        let text = segments.map(\.text).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { throw .noSpeechDetected }
        Log.recognition.info(
            "Whisper finished; segments=\(segments.count, privacy: .public) task=\(request.task.rawValue, privacy: .public)"
        )
        return Transcript(
            text: text,
            segments: segments,
            engine: descriptor.id,
            language: request.task == .translateToEnglish ? "en" : language,
            spokenLanguage: language,
            audioDuration: request.audio.duration,
            processingDuration: (ContinuousClock.now - start).seconds
        )
    }

    /// Releases the model's memory. The next recognition loads it again.
    public func unload() async {
        if model != nil {
            Log.recognition.info("Whisper model unloaded")
        }
        model = nil
        loaded = nil
    }

    /// Whether a model is loaded (for tests and memory diagnostics).
    var isLoaded: Bool { model != nil }

    /// The installed file; `verified` also checks it against the catalog (E5-S3).
    private func modelFile(_ asset: ModelAsset, verified: Bool) async -> URL? {
        guard let file = asset.files.first else { return nil }
        return verified
            ? await assets.verifiedFile(for: asset.id, named: file.name)
            : await assets.installedFile(for: asset.id, named: file.name)
    }

    /// Runs inference off the actor; cancellation sets the abort flag that
    /// whisper.cpp polls between decoding steps.
    /// Vocabulary as an initial prompt ("Glossary: A, B, C."), whole terms
    /// only, at most ``maximumPromptLength`` characters; `nil` without hints.
    static func prompt(for hints: [String]) -> String? {
        var terms: [String] = []
        var length = 0
        for hint in hints {
            let term = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, length + term.count + 2 <= maximumPromptLength else { continue }
            terms.append(term)
            length += term.count + 2
        }
        return terms.isEmpty ? nil : "Glossary: \(terms.joined(separator: ", "))."
    }

    /// Whisper's prompt window is about 224 tokens; this stays well inside it.
    static let maximumPromptLength = 400

    /// Detection must be this sure of one candidate language (E9-S2, Proposed
    /// until the quality thresholds are approved in E9-S6).
    static let minimumDetectionConfidence: Float = 0.6
    /// The candidate languages together must hold at least this much of the
    /// probability, or the speech is probably another language.
    static let minimumCandidateMass: Float = 0.5

    /// The most probable of `candidates`, or `nil` when the speech is
    /// probably another language or no candidate is clearly ahead. Pure.
    static func choose(from probabilities: [LanguageProbability], among candidates: [String]) -> String? {
        let relevant = probabilities.filter { candidates.contains($0.code) }
        let mass = relevant.reduce(0) { $0 + $1.probability }
        guard mass >= minimumCandidateMass, let best = relevant.max(by: { $0.probability < $1.probability }) else {
            return nil
        }
        return best.probability / mass >= minimumDetectionConfidence ? best.code : nil
    }

    /// The two-letter code to run with: the requested language, or the
    /// detected one. Detection never falls back to English (E9-S2).
    private static func spokenLanguage(
        for requested: String, samples: [Float], with model: any WhisperModel, threads: Int
    ) async throws(RecognitionError) -> String {
        guard SpokenLanguages.isAutomatic(requested) else { return SpokenLanguages.code(of: requested) }
        let detection = Task.detached { try model.detectLanguage(samples, threads: threads) }
        let probabilities: [LanguageProbability]
        do {
            probabilities = try await withTaskCancellationHandler {
                try await detection.value
            } onCancel: {
                detection.cancel()
            }
        } catch {
            throw Task.isCancelled ? .cancelled : (error as? RecognitionError ?? .engineFailure(code: -1))
        }
        if Task.isCancelled { throw .cancelled }
        guard let language = choose(from: probabilities, among: SpokenLanguages.detectionCandidates) else {
            throw .languageUncertain
        }
        return language
    }

    private static func transcribe(
        _ samples: [Float],
        with model: any WhisperModel,
        inference: WhisperInference,
        updates: @escaping @Sendable (RecognitionUpdate) -> Void
    ) async throws(RecognitionError) -> [TranscriptSegment] {
        let abort = AbortFlag()
        let inference = Task.detached {
            try model.transcribe(
                samples, inference,
                shouldAbort: { abort.isSet },
                progress: { updates(.progress($0)) })
        }
        do {
            return try await withTaskCancellationHandler {
                try await inference.value
            } onCancel: {
                abort.set()
            }
        } catch {
            if Task.isCancelled || abort.isSet { throw .cancelled }
            throw error as? RecognitionError ?? .engineFailure(code: -1)
        }
    }
}
