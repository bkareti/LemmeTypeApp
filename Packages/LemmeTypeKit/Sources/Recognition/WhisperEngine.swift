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

    public init(
        choice: WhisperModelChoice = .automatic,
        order: [ModelAssetID] = [.whisperBaseEnglish, .whisperSmallEnglish, .whisperTinyEnglish],
        threads: Int = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)),
        usesGPU: Bool = true
    ) {
        self.choice = choice
        self.order = order
        self.threads = threads
        self.usesGPU = usesGPU
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
    private var model: (any WhisperModel)?
    private var loaded: (url: URL, usesGPU: Bool)?

    public init(
        assets: any ModelAssetManaging, hardware: HardwareProfile = .current,
        settings: @escaping @Sendable () -> WhisperRunSettings = { WhisperRunSettings() }
    ) {
        self.init(assets: assets, hardware: hardware, runtime: WhisperCppRuntime(), settings: settings)
    }

    init(
        assets: any ModelAssetManaging,
        hardware: HardwareProfile,
        runtime: any WhisperRuntime,
        models: [ModelAsset] = ModelCatalog.whisperModels,
        settings: @escaping @Sendable () -> WhisperRunSettings = { WhisperRunSettings() }
    ) {
        self.models = models
        self.assets = assets
        self.hardware = hardware
        self.runtime = runtime
        self.settings = settings
        descriptor = EngineDescriptor(
            id: .whisper,
            supportedLanguages: ["en"],
            // The default download offered from Settings › Dictation.
            assets: .downloadable(.whisperBaseEnglish),
            capabilities: [.segmentTimings, .progress]
        )
    }

    /// Hardware is checked before assets, so an incompatible Mac is never
    /// offered the download.
    public func availability() async -> EngineAvailability {
        switch await resolve(settings()) {
        case .success: .ready
        case .failure(.unsupported(let reason)): .unsupported(reason)
        case .failure: .assetsMissing
        }
    }

    /// The model this session runs: the specific choice, or the first
    /// installed model in the plan's order that this Mac supports.
    private func resolve(_ settings: WhisperRunSettings) async -> Result<ModelAsset, RecognitionError> {
        let candidates: [ModelAsset]
        switch settings.choice {
        case .specific(let id):
            candidates = models.filter { $0.id == id }
        case .automatic:
            candidates = settings.order.compactMap { id in models.first { $0.id == id } }
        }
        var unsupported: UnsupportedReason?
        for asset in candidates {
            if let reason = asset.hardware.unsupportedReason(for: hardware) {
                unsupported = unsupported ?? reason
                continue
            }
            if await modelFile(asset, verified: false) != nil { return .success(asset) }
        }
        let anySupported = candidates.contains { $0.hardware.unsupportedReason(for: hardware) == nil }
        if let unsupported, !anySupported { return .failure(.unsupported(unsupported)) }
        return .failure(.assetsMissing)
    }

    public func prepare() async throws(RecognitionError) {
        let settings = settings()
        let asset = try await resolve(settings).get()
        if model != nil, let loaded, loaded.usesGPU == settings.usesGPU,
            await modelFile(asset, verified: false) == loaded.url
        {
            return
        }
        guard let url = await modelFile(asset, verified: true) else { throw .assetsMissing }
        model = nil
        loaded = nil
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
    }

    public func recognize(
        _ request: RecognitionRequest,
        updates: @escaping @Sendable (RecognitionUpdate) -> Void
    ) async throws(RecognitionError) -> Transcript {
        if Task.isCancelled { throw .cancelled }
        if let error = await availability().recognitionError { throw error }
        guard descriptor.supports(language: request.language) else { throw .unsupported(.language) }
        guard request.audio.duration >= SpeechActivity.minimumDuration else { throw .noSpeechDetected }
        try await prepare()
        guard let model else { throw .modelLoadFailed }
        let threads = settings().threads

        let start = ContinuousClock.now
        let segments = try await Self.transcribe(
            try AudioFileReader.readSamples(from: request.audio.fileURL), with: model,
            prompt: Self.prompt(for: request.hints), threads: threads, updates: updates)
        if Task.isCancelled { throw .cancelled }
        let text = segments.map(\.text).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { throw .noSpeechDetected }
        Log.recognition.info("Whisper finished; segments=\(segments.count, privacy: .public)")
        return Transcript(
            text: text,
            segments: segments,
            engine: descriptor.id,
            language: request.language,
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

    private static func transcribe(
        _ samples: [Float],
        with model: any WhisperModel,
        prompt: String?,
        threads: Int,
        updates: @escaping @Sendable (RecognitionUpdate) -> Void
    ) async throws(RecognitionError) -> [TranscriptSegment] {
        guard !samples.isEmpty, !SpeechActivity.isSilent(samples) else { throw .noSpeechDetected }
        let abort = AbortFlag()
        let inference = Task.detached {
            try model.transcribe(
                samples, WhisperInference(language: "en", prompt: prompt, threads: threads),
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
