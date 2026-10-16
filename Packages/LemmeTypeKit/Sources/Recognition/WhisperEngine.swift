import Domain
import Foundation
import Support

/// The downloadable Whisper model (whisper.cpp, `base.en`) behind the engine
/// contract. Runs entirely on this Mac; see docs/decisions/0012-local-whisper-model.md.
///
/// The model is loaded by ``prepare()`` (warm-up) and kept until ``unload()``.
/// Audio samples exist only for the duration of ``recognize(_:updates:)``.
public actor WhisperEngine: SpeechRecognitionEngine {
    public nonisolated let descriptor: EngineDescriptor

    private let asset: ModelAsset
    private let assets: any ModelAssetManaging
    private let hardware: HardwareProfile
    private let runtime: any WhisperRuntime
    private var model: (any WhisperModel)?
    private var loadedFrom: URL?

    public init(assets: any ModelAssetManaging, hardware: HardwareProfile = .current) {
        self.init(assets: assets, hardware: hardware, runtime: WhisperCppRuntime())
    }

    init(
        assets: any ModelAssetManaging,
        hardware: HardwareProfile,
        runtime: any WhisperRuntime,
        asset: ModelAsset = ModelCatalog.whisperBaseEnglish
    ) {
        self.asset = asset
        self.assets = assets
        self.hardware = hardware
        self.runtime = runtime
        descriptor = EngineDescriptor(
            id: .whisper,
            supportedLanguages: asset.languages,
            assets: .downloadable(asset.id),
            capabilities: [.segmentTimings, .progress]
        )
    }

    /// Hardware is checked before assets, so an incompatible Mac is never
    /// offered the download.
    public func availability() async -> EngineAvailability {
        if let reason = asset.hardware.unsupportedReason(for: hardware) {
            return .unsupported(reason)
        }
        return await modelFile() == nil ? .assetsMissing : .ready
    }

    public func prepare() async throws(RecognitionError) {
        if let reason = asset.hardware.unsupportedReason(for: hardware) { throw .unsupported(reason) }
        guard let url = await modelFile() else { throw .assetsMissing }
        if model != nil && loadedFrom == url { return }
        model = nil
        let runtime = self.runtime
        // Loading cannot be interrupted inside whisper.cpp, so it runs
        // detached: a cancelled warm-up returns at once and the loaded model
        // is released as soon as loading finishes.
        let loading = Task.detached { try runtime.loadModel(at: url) }
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
        loadedFrom = url
        Log.recognition.info("Whisper model loaded")
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

        let start = ContinuousClock.now
        let segments = try await Self.transcribe(
            try AudioFileReader.readSamples(from: request.audio.fileURL), with: model, updates: updates)
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
        loadedFrom = nil
    }

    /// Whether a model is loaded (for tests and memory diagnostics).
    var isLoaded: Bool { model != nil }

    private func modelFile() async -> URL? {
        guard let file = asset.files.first else { return nil }
        return await assets.installedFile(for: asset.id, named: file.name)
    }

    /// Runs inference off the actor; cancellation sets the abort flag that
    /// whisper.cpp polls between decoding steps.
    private static func transcribe(
        _ samples: [Float],
        with model: any WhisperModel,
        updates: @escaping @Sendable (RecognitionUpdate) -> Void
    ) async throws(RecognitionError) -> [TranscriptSegment] {
        guard !samples.isEmpty, !SpeechActivity.isSilent(samples) else { throw .noSpeechDetected }
        let abort = AbortFlag()
        let inference = Task.detached {
            try model.transcribe(
                samples, language: "en", shouldAbort: { abort.isSet }, progress: { updates(.progress($0)) })
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
