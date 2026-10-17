import Foundation

/// How the transcript is written before delivery (E2-S6).
public enum WritingMode: String, CaseIterable, Codable, Sendable {
    /// Only the normalisation needed for delivery; words are never changed.
    case exact
    /// Deterministic cleanup: capitalisation, punctuation, fillers, self-corrections.
    case clean
}

/// The user's engine choice, read when a recording starts.
public struct EnginePreference: Equatable, Sendable {
    /// `nil` means Automatic.
    public var selected: RecognitionEngineID?
    /// Use another ready engine instead of asking when `selected` isn't ready.
    public var fallsBackAutomatically: Bool

    public init(selected: RecognitionEngineID? = nil, fallsBackAutomatically: Bool = false) {
        self.selected = selected
        self.fallsBackAutomatically = fallsBackAutomatically
    }

    public static let automatic = EnginePreference()
}

/// One recording on its way to text. Owns the target, the audio file, the
/// engine (fixed when processing first starts), and the mode for its whole
/// life, so settings changes only affect later sessions. Mode, language, and
/// engine preference are read when the recording starts.
public struct DictationSession: Identifiable, Sendable {
    public let id: UUID
    public let audio: RecordedAudio
    public let target: ActivationTarget?
    public let mode: WritingMode
    public let language: String
    /// The engine choice in Settings when recording started.
    public let enginePreference: EnginePreference
    /// `nil` until the pipeline picks one; retries reuse it.
    public var engine: RecognitionEngineID?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        audio: RecordedAudio,
        target: ActivationTarget?,
        mode: WritingMode,
        language: String,
        enginePreference: EnginePreference = .automatic,
        engine: RecognitionEngineID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.audio = audio
        self.target = target
        self.mode = mode
        self.language = language
        self.enginePreference = enginePreference
        self.engine = engine
        self.createdAt = createdAt
    }

    /// Text near the cursor captured for formatting at activation, if allowed.
    public var formattingContext: CursorContext? {
        if case .captured(let context, .formatting) = target?.context { return context }
        return nil
    }

    /// The context outcome for diagnostics: an identifier, never text.
    public var contextIdentifier: String {
        target?.context.identifier ?? ContextCapture.notRequested.identifier
    }

    /// Deletes the session's temporary audio. Safe to call more than once.
    public func discardAudio() {
        try? FileManager.default.removeItem(at: audio.fileURL)
    }
}

/// What the processing step is doing, for the overlay.
public enum ProcessingPhase: String, Sendable {
    case preparingEngine = "preparing-engine"
    case recognizing
    case writing
    case delivering
}

public enum ProcessingUpdate: Equatable, Sendable {
    case phase(ProcessingPhase)
    /// Recognition progress, 0...1.
    case progress(Double)
}

/// A processing result that needs the user's decision. The recording (and
/// any transcript) is kept until the user acts or the session is discarded.
public enum DictationIssue: Equatable, Sendable {
    case recognitionFailed(RecognitionError)
    /// The chosen engine cannot run (assets, permission, hardware).
    case engineUnavailable(RecognitionEngineID, EngineAvailability)
    /// No local engine is ready.
    case noEngineAvailable
    /// Text was produced but could not be delivered.
    case deliveryFailed(DeliveryProblem)

    /// Stable lowercase name for diagnostics.
    public var identifier: String {
        switch self {
        case .recognitionFailed(let error): error.identifier
        case .engineUnavailable(_, let availability): "engine.\(availability.identifier)"
        case .noEngineAvailable: "engine.none-available"
        case .deliveryFailed(let problem): "delivery.\(problem.rawValue)"
        }
    }
}

/// Choices offered for a ``DictationIssue``.
public enum DictationAction: Equatable, Sendable {
    /// Run the same engine again on the same recording.
    case retry
    /// Run another ready engine on the same recording.
    case useEngine(RecognitionEngineID)
    /// Request (or open settings for) Speech Recognition authorization.
    case allowSpeechRecognition
    /// Open engine settings.
    case chooseEngine
    /// Save a copy of the recording where the user chooses.
    case saveAudio
    /// Copy the transcript to the clipboard.
    case copyText
    /// Try delivering the transcript to the original field again.
    case retryDelivery
    case openPermissions
    /// Delete the recording and transcript.
    case discard
}

extension DictationIssue {
    /// The actions to offer, most useful first. `alternatives` are other
    /// engines that are ready now.
    public func actions(alternatives: [RecognitionEngineID]) -> [DictationAction] {
        let switchEngine = alternatives.map(DictationAction.useEngine)
        switch self {
        case .recognitionFailed(.permissionDenied), .engineUnavailable(_, .permissionUnavailable):
            return [.allowSpeechRecognition, .retry] + switchEngine + [.saveAudio, .discard]
        case .recognitionFailed(.noSpeechDetected):
            return [.discard]
        case .recognitionFailed(let error) where error.isRetryable:
            return [.retry] + switchEngine + [.saveAudio, .discard]
        case .recognitionFailed, .engineUnavailable, .noEngineAvailable:
            return switchEngine + [.chooseEngine, .saveAudio, .discard]
        case .deliveryFailed(.targetChanged):
            return [.copyText, .retryDelivery, .discard]
        case .deliveryFailed(.permissionMissing):
            return [.copyText, .openPermissions, .discard]
        case .deliveryFailed:
            return [.copyText, .discard]
        }
    }
}

/// How a session's processing ended.
public enum DictationOutcome: Equatable, Sendable {
    case delivered(DeliveryMethod)
    /// `transcript` is kept in memory only, for Copy and Retry Delivery.
    case needsAttention(
        DictationIssue, engine: RecognitionEngineID?, alternatives: [RecognitionEngineID], transcript: String?)
    case cancelled
}

/// Turns a session's recording into delivered text (E2-S5).
public protocol DictationProcessing: Sendable {
    /// Selects the engine (unless the session already has one), recognises,
    /// applies the session's writing mode, and delivers. Deletes the audio
    /// after successful delivery; otherwise the session keeps it.
    func process(
        _ session: DictationSession,
        updates: @escaping @Sendable (ProcessingUpdate) -> Void
    ) async -> DictationOutcome

    /// Delivers an already produced transcript again (Retry Delivery).
    func deliver(_ transcript: String, for session: DictationSession) async -> DictationOutcome
}
