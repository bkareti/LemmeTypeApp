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
            capabilities: provider.detectsLanguage ? [.progress, .languageDetection] : [.progress],
            tasks: provider.tasks)
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

        let rate = AudioCaptureFormat.speech.sampleRate
        let seconds = Double(samples.count) / rate
        let answers = try await transcribeParts(of: samples, need: need, credential: credential, updates: updates)
        if Task.isCancelled { throw .cancelled }

        let text = answers.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
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

    /// Sends each part in order, one at a time. Any failure ends the whole
    /// recognition, so partial text is never delivered as if it were complete.
    private func transcribeParts(
        of samples: [Float], need: RecognitionNeed, credential: CloudCredential,
        updates: @Sendable (RecognitionUpdate) -> Void
    ) async throws(RecognitionError) -> [String] {
        let rate = AudioCaptureFormat.speech.sampleRate
        let parts = SpeechSplitter.ranges(of: samples, sampleRate: rate, maximumSeconds: provider.maximumClipSeconds)
        var answers: [String] = []
        for (index, range) in parts.enumerated() {
            if Task.isCancelled { throw .cancelled }
            let part = Array(samples[range])
            // A silent stretch costs money and can only come back empty.
            if !SpeechActivity.isSilent(part) {
                let clip = CloudAudioClip(wav: WAVEncoder.encode(part), seconds: Double(part.count) / rate)
                answers.append(try await send(try provider.request(for: clip, need: need, credential: credential)))
            }
            if parts.count > 1 { updates(.progress(Double(index + 1) / Double(parts.count))) }
        }
        return answers
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
