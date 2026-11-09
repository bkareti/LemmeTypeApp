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
    /// The opt-in cloud engine (ADR 0031). Vendor-neutral on purpose: saved
    /// preferences and modes keep working when the provider changes.
    public static let cloud = RecognitionEngineID(rawValue: "cloud")

    /// Whether audio leaves the device. Such an engine runs only when the user chose it.
    public var isCloud: Bool { self == .cloud }
}

/// Where recognition runs. A cloud engine is always a visible, opt-in choice
/// (docs/decisions/0031-cloud-speech-provider.md).
public enum ProcessingLocation: String, Codable, Sendable {
    case onDevice
    case cloud
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
    /// Detects the spoken language when asked for ``SpokenLanguages/automatic`` (E9-S2).
    public static let languageDetection = EngineCapabilities(rawValue: 1 << 4)
}

/// Static, provider-neutral facts about an engine.
public struct EngineDescriptor: Equatable, Sendable {
    public let id: RecognitionEngineID
    public let location: ProcessingLocation
    /// BCP 47 identifiers such as `"en-US"`. The MVP supports English only.
    public let supportedLanguages: [String]
    public let assets: AssetRequirement
    public let capabilities: EngineCapabilities
    /// What the engine can be asked to do. Every engine transcribes.
    public let tasks: Set<RecognitionTask>

    public init(
        id: RecognitionEngineID,
        location: ProcessingLocation = .onDevice,
        supportedLanguages: [String],
        assets: AssetRequirement,
        capabilities: EngineCapabilities,
        tasks: Set<RecognitionTask> = [.transcribe]
    ) {
        self.id = id
        self.location = location
        self.supportedLanguages = supportedLanguages
        self.assets = assets
        self.capabilities = capabilities
        self.tasks = tasks
    }

    /// Whether `language` (for example `"en-GB"`) is supported, matching on
    /// the language code when the engine lists a bare code such as `"en"`.
    public func supports(language: String) -> Bool {
        let code = language.split(separator: "-").first.map(String.init) ?? language
        return supportedLanguages.contains { $0 == language || $0 == code }
    }

    /// Whether the engine can take `need`: the language (or detection, for
    /// Automatic) and the task. Says nothing about installed assets.
    public func supports(_ need: RecognitionNeed) -> Bool {
        guard tasks.contains(need.task) else { return false }
        if SpokenLanguages.isAutomatic(need.language) { return capabilities.contains(.languageDetection) }
        return supports(language: need.language)
    }
}

/// A language and task an engine is asked to serve (E9-S2).
public struct RecognitionNeed: Equatable, Hashable, Sendable {
    /// A BCP 47 identifier or ``SpokenLanguages/automatic``.
    public let language: String
    public let task: RecognitionTask

    public init(language: String, task: RecognitionTask = .transcribe) {
        self.language = language
        self.task = task
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
    /// A BCP 47 identifier, or ``SpokenLanguages/automatic`` (E9-S2).
    public let language: String
    /// Transcribe in the spoken language, or write English (E9-S2).
    public let task: RecognitionTask
    /// Words and names the user expects (vocabulary terms, E4-S2). Engines may
    /// use them to bias recognition; they are never logged and never leave the Mac.
    public let hints: [String]

    public init(audio: RecordedAudio, language: String, task: RecognitionTask = .transcribe, hints: [String] = []) {
        self.audio = audio
        self.language = language
        self.task = task
        self.hints = hints
    }

    public var need: RecognitionNeed { RecognitionNeed(language: language, task: task) }
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

    /// Availability for one language and task (E9-S2): ``availability()``
    /// plus whether the installed assets can serve `need`. Must not prompt or
    /// download. The default serves engines whose assets do not depend on the language.
    func availability(for need: RecognitionNeed) async -> EngineAvailability

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

extension SpeechRecognitionEngine {
    public func availability(for need: RecognitionNeed) async -> EngineAvailability {
        guard descriptor.supports(need) else { return .unsupported(.language) }
        return await availability()
    }
}
