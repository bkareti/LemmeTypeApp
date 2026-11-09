import Domain
import Foundation
import Support

/// The one cloud engine the app knows about (docs/decisions/0031-cloud-speech-provider.md).
/// It owns everything that does not depend on the vendor; ``CloudSpeechProvider``
/// owns everything that does.
///
/// Audio is converted in memory and sent once per attempt. Vocabulary hints in
/// the request are deliberately not passed on: they never leave the Mac.
public struct CloudSpeechEngine: SpeechRecognitionEngine {
    /// Attempts after the first, for rate limits and server errors only.
    public static let maximumRetries = 2
    static let firstRetryDelay: Duration = .seconds(1)

    private let provider: any CloudSpeechProvider
    private let transport: any CloudSpeechTransport
    private let credentials: any CloudCredentialProviding
    private let clock: any Clock<Duration>
    private let diagnostics: any DiagnosticsRecording

    public init(
        provider: any CloudSpeechProvider,
        transport: any CloudSpeechTransport,
        credentials: any CloudCredentialProviding,
        clock: any Clock<Duration> = ContinuousClock(),
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.provider = provider
        self.transport = transport
        self.credentials = credentials
        self.clock = clock
        self.diagnostics = diagnostics
    }

    public var descriptor: EngineDescriptor {
        EngineDescriptor(
            id: .cloud, location: .cloud, supportedLanguages: provider.supportedLanguages, assets: .none,
            capabilities: [], tasks: provider.tasks)
    }

    public func availability() async -> EngineAvailability {
        await credentials.credential(for: provider.id) == nil ? .permissionUnavailable : .ready
    }

    public func prepare() async throws(RecognitionError) {}

    public func unload() async {}

    public func recognize(
        _ request: RecognitionRequest,
        updates: @escaping @Sendable (RecognitionUpdate) -> Void
    ) async throws(RecognitionError) -> Transcript {
        if Task.isCancelled { throw .cancelled }
        let need = request.need
        if let error = await availability(for: need).recognitionError { throw error }
        guard request.audio.duration >= SpeechActivity.minimumDuration else { throw .noSpeechDetected }

        let start = ContinuousClock.now
        let samples = try AudioFileReader.readSamples(from: request.audio.fileURL)
        guard !samples.isEmpty else { throw .noSpeechDetected }
        // Checked before anything is sent: a silent recording must cost nothing.
        guard !SpeechActivity.isSilent(samples) else { throw .silentAudio }
        guard let credential = await credentials.credential(for: provider.id) else { throw .permissionDenied }

        let seconds = Double(samples.count) / AudioCaptureFormat.speech.sampleRate
        // Until long recordings are sent in parts (E11-S2).
        guard seconds <= provider.maximumClipSeconds else { throw .cloudServiceFailed }

        let clip = CloudAudioClip(wav: WAVEncoder.encode(samples), seconds: seconds)
        let outgoing = try provider.request(for: clip, need: need, credential: credential)
        let answer = try await send(outgoing)
        if Task.isCancelled { throw .cancelled }

        let text = answer.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { throw .noSpeechDetected }
        let elapsed = start.duration(to: .now).components
        diagnostics.record(
            .recognition, "cloud-recognized", ["provider": .id(provider.id.rawValue), "seconds": .seconds(seconds)])
        return Transcript(
            text: text,
            engine: .cloud,
            language: need.task == .translateToEnglish ? SpokenLanguages.english.code : request.language,
            spokenLanguage: request.language,
            audioDuration: request.audio.duration,
            processingDuration: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }

    private func send(_ request: CloudHTTPRequest) async throws(RecognitionError) -> String {
        var retriesLeft = Self.maximumRetries
        var delay = Self.firstRetryDelay
        while true {
            if Task.isCancelled { throw .cancelled }
            let response: CloudHTTPResponse
            do {
                response = try await transport.send(request)
            } catch {
                throw report(Self.recognitionError(for: error))
            }
            let failure: RecognitionError
            do {
                return try provider.transcript(from: response)
            } catch {
                failure = error
            }
            guard retriesLeft > 0, Self.isWorthRetrying(failure, status: response.status) else {
                throw report(failure)
            }
            retriesLeft -= 1
            do {
                try await clock.sleep(for: delay)
            } catch {
                throw .cancelled
            }
            delay *= 2
        }
    }

    private func report(_ error: RecognitionError) -> RecognitionError {
        if error != .cancelled {
            diagnostics.record(
                .recognition, "cloud-failed", ["provider": .id(provider.id.rawValue), "error": .id(error.identifier)])
            Log.recognition.error("Cloud speech failed; error=\(error.identifier, privacy: .public)")
        }
        return error
    }

    /// Only what can clear up by itself. A used-up balance or a bad key cannot.
    static func isWorthRetrying(_ error: RecognitionError, status: Int) -> Bool {
        error == .cloudRateLimited || (error == .cloudServiceFailed && (500...599).contains(status))
    }

    static func recognitionError(for failure: CloudTransportFailure) -> RecognitionError {
        switch failure {
        case .cancelled: .cancelled
        case .offline: .cloudOffline
        case .timedOut, .hostRefused, .failed: .cloudServiceFailed
        }
    }
}
