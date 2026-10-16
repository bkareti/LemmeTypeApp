import Foundation

/// The single audio format LemmeType hands to speech recognition: 16 kHz,
/// mono, 32-bit float linear PCM. Accepted by Apple Speech and Whisper-class
/// models, and small enough to keep in memory for short dictations.
public struct AudioCaptureFormat: Equatable, Sendable {
    public let sampleRate: Double
    public let channelCount: Int
    public let encoding: Encoding

    public enum Encoding: String, Sendable {
        case float32PCM
    }

    public static let speech = AudioCaptureFormat(sampleRate: 16_000, channelCount: 1, encoding: .float32PCM)
}

/// Which microphone to record from. Persisted as the user's choice.
public enum AudioInputSelection: Hashable, Codable, Sendable {
    case systemDefault
    case device(id: String)
}

/// A block of captured audio in ``AudioCaptureFormat/speech``.
public struct AudioChunk: Sendable {
    public let samples: [Float]
    public let format: AudioCaptureFormat

    public init(samples: [Float], format: AudioCaptureFormat = .speech) {
        self.samples = samples
        self.format = format
    }

    public var duration: TimeInterval { Double(samples.count) / format.sampleRate }
}

/// A finished recording, stored in LemmeType's protected temporary directory.
/// The consumer deletes it after transcription.
public struct RecordedAudio: Sendable {
    public let fileURL: URL
    public let duration: TimeInterval
    public let format: AudioCaptureFormat

    public init(fileURL: URL, duration: TimeInterval, format: AudioCaptureFormat) {
        self.fileURL = fileURL
        self.duration = duration
        self.format = format
    }
}

/// Something that happened during a capture session.
public enum AudioCaptureEvent: Sendable {
    /// New audio in the speech format.
    case audio(AudioChunk)
    /// Input level, 0 (silence) to 1 (full scale), for a meter. Never logged.
    case level(Float)
    /// The chosen device was unavailable, so the system default is being used.
    case fellBackToSystemDefault
    /// Capture ended unexpectedly; the partial recording was deleted.
    case failed(AudioCaptureError)
}

public enum AudioCaptureError: LemmeTypeError, Equatable {
    case microphonePermissionMissing
    case noInputDevice
    case deviceDisconnected
    /// The system went to sleep or another client took the input.
    case interrupted
    case alreadyCapturing
    case notCapturing
    case engineFailure(code: Int32)
    case storageFailure

    public var identifier: String {
        switch self {
        case .microphonePermissionMissing: "audio.permission-missing"
        case .noInputDevice: "audio.no-input-device"
        case .deviceDisconnected: "audio.device-disconnected"
        case .interrupted: "audio.interrupted"
        case .alreadyCapturing: "audio.already-capturing"
        case .notCapturing: "audio.not-capturing"
        case .engineFailure: "audio.engine-failure"
        case .storageFailure: "audio.storage-failure"
        }
    }
}

/// Records microphone audio for one dictation at a time.
public protocol AudioCapturing: Sendable {
    /// Starts capturing. Events arrive on the returned stream, which finishes
    /// when the session stops, is cancelled, or fails.
    func start(input: AudioInputSelection) async throws(AudioCaptureError) -> AsyncStream<AudioCaptureEvent>
    /// Stops capturing and returns the finished recording.
    func stop() async throws(AudioCaptureError) -> RecordedAudio
    /// Stops capturing and deletes everything recorded in this session.
    func cancel() async
    /// Deletes recordings left behind by a crash or forced quit.
    func purgeLeftovers() async
}

/// The hardware edge: delivers mono float buffers at the device's sample rate.
public protocol AudioSource: Sendable {
    /// Starts the input. Returns whether it had to fall back to the system default.
    func start(
        input: AudioInputSelection,
        onEvent: @escaping @Sendable (AudioSourceEvent) -> Void
    ) throws(AudioCaptureError) -> AudioSourceStart
    func stop()
}

public struct AudioSourceStart: Equatable, Sendable {
    public let usedSystemDefaultFallback: Bool

    public init(usedSystemDefaultFallback: Bool) {
        self.usedSystemDefaultFallback = usedSystemDefaultFallback
    }
}

public enum AudioSourceEvent: Sendable {
    /// Mono samples at `sampleRate`.
    case buffer([Float], sampleRate: Double)
    case deviceLost
    case interrupted
}
