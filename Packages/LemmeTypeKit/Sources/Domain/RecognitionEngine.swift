import Foundation

/// Stable identity of a speech-recognition engine. Persisted in preferences
/// and written to diagnostics, so raw values never change once shipped.
public struct RecognitionEngineID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    /// Apple's on-device speech recognition (E2-S2).
    public static let appleSpeech = RecognitionEngineID(rawValue: "apple-speech")
    /// The optional downloadable Whisper model (E2-S3).
    public static let whisper = RecognitionEngineID(rawValue: "whisper")
}

/// Where recognition runs. Only on-device engines exist in the MVP; the type
/// makes any future cloud engine impossible to add without a visible change.
public enum ProcessingLocation: String, Codable, Sendable {
    case onDevice
}

/// What an engine needs installed before it can run.
public enum AssetRequirement: Equatable, Sendable {
    /// Nothing beyond the app.
    case none
    /// Assets macOS downloads and manages (for example speech dictation assets).
    case systemManaged
    /// A model LemmeType downloads after explicit confirmation (E2-S4).
    case downloadable(ModelAssetID)
}

/// Optional features an engine may offer.
public struct EngineCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Emits ``RecognitionUpdate/partial(_:)`` while recognising.
    public static let partialResults = EngineCapabilities(rawValue: 1 << 0)
    /// Fills ``TranscriptSegment`` timing.
    public static let segmentTimings = EngineCapabilities(rawValue: 1 << 1)
    /// Fills ``TranscriptSegment/confidence``.
    public static let confidence = EngineCapabilities(rawValue: 1 << 2)
    /// Emits ``RecognitionUpdate/progress(_:)``.
    public static let progress = EngineCapabilities(rawValue: 1 << 3)
}

/// Static, provider-neutral facts about an engine.
public struct EngineDescriptor: Equatable, Sendable {
    public let id: RecognitionEngineID
    public let location: ProcessingLocation
    /// BCP 47 identifiers such as `"en-US"`. The MVP supports English only.
    public let supportedLanguages: [String]
    public let assets: AssetRequirement
    public let capabilities: EngineCapabilities

    public init(
        id: RecognitionEngineID,
        location: ProcessingLocation = .onDevice,
        supportedLanguages: [String],
        assets: AssetRequirement,
        capabilities: EngineCapabilities
    ) {
        self.id = id
        self.location = location
        self.supportedLanguages = supportedLanguages
        self.assets = assets
        self.capabilities = capabilities
    }

    /// Whether `language` (for example `"en-GB"`) is supported, matching on
    /// the language code when the engine lists a bare code such as `"en"`.
    public func supports(language: String) -> Bool {
        let code = language.split(separator: "-").first.map(String.init) ?? language
        return supportedLanguages.contains { $0 == language || $0 == code }
    }
}

/// Why an engine cannot run on this Mac.
/// Raw values are stable diagnostics identifiers.
public enum UnsupportedReason: String, Codable, Sendable {
    case operatingSystem = "operating-system"
    case hardware
    case insufficientMemory = "insufficient-memory"
    case language
    /// The engine exists but only off-device recognition is available, which
    /// LemmeType never uses.
    case onDeviceRecognitionUnavailable = "on-device-unavailable"
}

/// Whether an engine can recognise speech right now.
public enum EngineAvailability: Equatable, Sendable {
    case ready
    /// Models or system speech assets must be installed first.
    case assetsMissing
    case unsupported(UnsupportedReason)
    /// A recognition authorization (separate from Microphone) is missing.
    case permissionUnavailable
    case failed(RecognitionError)

    public var isReady: Bool { self == .ready }

    /// Stable lowercase name for diagnostics.
    public var identifier: String {
        switch self {
        case .ready: "ready"
        case .assetsMissing: "assets-missing"
        case .unsupported(let reason): "unsupported.\(reason.rawValue)"
        case .permissionUnavailable: "permission-unavailable"
        case .failed(let error): "failed.\(error.identifier)"
        }
    }

    /// The error ``SpeechRecognitionEngine/recognize(_:updates:)`` must throw
    /// when asked to run in this state.
    public var recognitionError: RecognitionError? {
        switch self {
        case .ready: nil
        case .assetsMissing: .assetsMissing
        case .unsupported(let reason): .unsupported(reason)
        case .permissionUnavailable: .permissionDenied
        case .failed(let error): error
        }
    }
}

/// One recognition job: a finished recording and the language to use.
public struct RecognitionRequest: Sendable {
    public let audio: RecordedAudio
    public let language: String

    public init(audio: RecordedAudio, language: String) {
        self.audio = audio
        self.language = language
    }
}

/// Progress reported while an engine works. Partial text is shown in the
/// overlay only and never logged or persisted.
public enum RecognitionUpdate: Equatable, Sendable {
    /// Fraction complete, 0...1.
    case progress(Double)
    case partial(String)
}

/// A local speech-recognition engine.
///
/// Contract (verified for every engine by `RecognitionEngineContract` in
/// TestSupport):
/// - **Local only.** An engine must not initiate network requests while
///   preparing or recognising. Asset downloads are a separate, user-confirmed
///   step outside this protocol.
/// - **Availability first.** When ``availability()`` is not ``EngineAvailability/ready``,
///   ``recognize(_:updates:)`` throws ``EngineAvailability/recognitionError``
///   and never returns a transcript.
/// - **Cancellation.** Cancelling the calling task makes ``recognize(_:updates:)``
///   throw ``RecognitionError/cancelled`` promptly and stop all work; it never
///   returns a transcript or emits updates afterwards. ``RecognitionRunner``
///   enforces the last part for every engine.
/// - **No retention.** The engine does not keep audio or transcripts once
///   ``recognize(_:updates:)`` returns, and never deletes the request's audio
///   file (the session owns it).
public protocol SpeechRecognitionEngine: Sendable {
    var descriptor: EngineDescriptor { get }

    /// Current availability. Must not prompt for permissions or download anything.
    func availability() async -> EngineAvailability

    /// Optional warm-up (for example loading a model). Safe to call repeatedly.
    func prepare() async throws(RecognitionError)

    /// Recognises the whole request and returns one final transcript.
    func recognize(
        _ request: RecognitionRequest,
        updates: @escaping @Sendable (RecognitionUpdate) -> Void
    ) async throws(RecognitionError) -> Transcript

    /// Releases memory held by ``prepare()``. Safe to call at any time.
    func unload() async
}
