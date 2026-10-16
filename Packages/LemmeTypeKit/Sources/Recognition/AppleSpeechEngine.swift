import Domain
import Foundation
import Support

/// Apple's on-device speech recognition behind the engine contract.
///
/// Recognition always requires on-device processing: when macOS cannot
/// recognise the language on this Mac the engine reports
/// `unsupported(.onDeviceRecognitionUnavailable)` and never falls back to
/// Apple's servers.
public final class AppleSpeechEngine: SpeechRecognitionEngine {
    public static let languages = ["en-US", "en-GB", "en-AU", "en-CA", "en-IN", "en-IE", "en-NZ"]

    public let descriptor = EngineDescriptor(
        id: .appleSpeech,
        supportedLanguages: AppleSpeechEngine.languages,
        assets: .systemManaged,
        capabilities: [.partialResults, .segmentTimings, .confidence]
    )

    private let backend: any AppleSpeechBackend
    private let authorizer: any SpeechRecognitionAuthorizing
    private let language: @Sendable () -> String

    /// `language` returns the user’s dictation language; it is read whenever availability is checked.
    public convenience init(
        authorizer: any SpeechRecognitionAuthorizing,
        language: @escaping @Sendable () -> String
    ) {
        self.init(backend: SFSpeechBackend(), authorizer: authorizer, language: language)
    }

    init(
        backend: any AppleSpeechBackend,
        authorizer: any SpeechRecognitionAuthorizing,
        language: @escaping @Sendable () -> String
    ) {
        self.backend = backend
        self.authorizer = authorizer
        self.language = language
    }

    public func availability() async -> EngineAvailability {
        availability(for: language())
    }

    private func availability(for language: String) -> EngineAvailability {
        guard authorizer.status().isGranted else { return .permissionUnavailable }
        guard descriptor.supports(language: language), backend.hasRecognizer(language: language) else {
            return .unsupported(.language)
        }
        guard backend.supportsOnDeviceRecognition(language: language) else {
            return .unsupported(.onDeviceRecognitionUnavailable)
        }
        return .ready
    }

    /// Nothing to load: macOS manages the speech assets.
    public func prepare() async throws(RecognitionError) {
        if let error = availability(for: language()).recognitionError { throw error }
    }

    public func recognize(
        _ request: RecognitionRequest,
        updates: @escaping @Sendable (RecognitionUpdate) -> Void
    ) async throws(RecognitionError) -> Transcript {
        try checkCancellation()
        if let error = availability(for: request.language).recognitionError { throw error }
        guard request.audio.duration >= SpeechActivity.minimumDuration else { throw .noSpeechDetected }
        let samples = try AudioFileReader.readSamples(from: request.audio.fileURL)
        guard !samples.isEmpty, !SpeechActivity.isSilent(samples) else { throw .noSpeechDetected }
        try checkCancellation()

        let start = ContinuousClock.now
        let result = try await backend.recognize(fileURL: request.audio.fileURL, language: request.language) {
            updates(.partial($0))
        }
        try checkCancellation()
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .noSpeechDetected }
        let elapsed = ContinuousClock.now - start
        Log.recognition.info(
            "Apple Speech finished; segments=\(result.segments.count, privacy: .public)")
        return Transcript(
            text: text,
            segments: result.segments,
            engine: descriptor.id,
            language: request.language,
            audioDuration: request.audio.duration,
            processingDuration: elapsed.seconds
        )
    }

    public func unload() async {}

    private func checkCancellation() throws(RecognitionError) {
        if Task.isCancelled { throw .cancelled }
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
