import Foundation

/// How the transcript is written before delivery (E2-S6).
public enum WritingMode: String, CaseIterable, Codable, Sendable {
    /// Only the normalisation needed for delivery; words are never changed.
    case exact
    /// Deterministic cleanup: capitalisation, punctuation, fillers, self-corrections.
    case clean
}

/// What a session's speech is for.
public enum SessionPurpose: String, Sendable {
    /// Dictate text at the cursor.
    case dictation
    /// Speak an instruction that rewrites the selection (E3-S5).
    case editing
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
    /// Every transcription, cleanup, style, and output choice for this
    /// session (E4-S5). ``mode`` is its writing mode.
    public let dictationMode: DictationMode
    /// Whether the mode came from the default or an app rule (E4-S7).
    public let modeSource: ModeSource
    public let purpose: SessionPurpose
    /// A BCP 47 identifier or ``SpokenLanguages/automatic``. Changes only
    /// when the user picks a language after uncertain detection (E9-S2).
    public var language: String
    /// Original text or English, captured when recording started (E9-S3).
    public let speechOutput: SpeechOutput
    /// The engine choice in Settings when recording started.
    public let enginePreference: EnginePreference
    /// `nil` until the pipeline picks one; retries reuse it.
    public var engine: RecognitionEngineID?
    /// The user's vocabulary, replacements, and snippets when recording
    /// started (E4-S2, E4-S3). In memory only.
    public let personalization: PersonalizationLibrary
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        audio: RecordedAudio,
        target: ActivationTarget?,
        mode: WritingMode,
        dictationMode: DictationMode? = nil,
        modeSource: ModeSource = .default,
        purpose: SessionPurpose = .dictation,
        language: String,
        speechOutput: SpeechOutput = .original,
        enginePreference: EnginePreference = .automatic,
        engine: RecognitionEngineID? = nil,
        personalization: PersonalizationLibrary = .empty,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.audio = audio
        self.target = target
        self.mode = mode
        self.dictationMode = dictationMode ?? .builtIn(for: mode)
        self.modeSource = modeSource
        self.purpose = purpose
        self.language = language
        self.speechOutput = speechOutput
        self.enginePreference = enginePreference
        self.engine = engine
        self.personalization = personalization
        self.createdAt = createdAt
    }

    /// Text near the cursor captured for formatting at activation, if allowed.
    public var formattingContext: CursorContext? {
        if case .captured(let context, .formatting) = target?.context { return context }
        return nil
    }

    /// The selection captured for voice editing, with its text.
    public var editingContext: CursorContext? {
        if case .captured(let context, .editing) = target?.context, context.selectedText != nil { return context }
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
    /// Rewriting the selection with the on-device model (voice editing).
    case rewriting
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
    /// Voice editing can't start: no selection, excluded app, password field, … (E3-S5).
    case editingUnavailable(ContextBlockReason)
    /// The on-device language model can't run.
    case rewriterUnavailable(RewriterAvailability)
    /// The model did not produce an edit; the selection is unchanged.
    case rewriteFailed(RewriteError)
    /// The chosen language and output cannot run; nothing was recorded (E9-S3).
    case languageUnavailable(LanguageReadiness)
    /// A translation to read before it is inserted or copied (E9-S5).
    case reviewTranslation
    /// A rewrite in the chosen tone and format to read before it is inserted
    /// or copied; `notice` is set when the rewrite did not apply (E10-S4).
    case reviewRewrite(RewriteNotice?)

    /// Stable lowercase name for diagnostics.
    public var identifier: String {
        switch self {
        case .recognitionFailed(let error): error.identifier
        case .engineUnavailable(_, let availability): "engine.\(availability.identifier)"
        case .noEngineAvailable: "engine.none-available"
        case .deliveryFailed(let problem): "delivery.\(problem.rawValue)"
        case .editingUnavailable(let reason): "editing.\(reason.rawValue)"
        case .rewriterUnavailable(let availability): "rewrite.\(availability.identifier)"
        case .rewriteFailed(let error): error.identifier
        case .languageUnavailable(let readiness): "language.\(readiness.identifier)"
        case .reviewTranslation: "review.translation"
        case .reviewRewrite(let notice): notice.map { "review.\($0.identifier)" } ?? "review.rewrite"
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
    /// Open Settings › Context (voice editing and context controls).
    case openContextSettings
    /// Process the recording again in this language (E9-S2).
    case useLanguage(String)
    /// Open Settings › Dictation to choose a language or download a model (E9-S3).
    case chooseLanguage
    /// Deliver the text being reviewed to the original field (E9-S5).
    case insertText
    /// Deliver the text from before the rewrite instead of the rewrite (E10-S4).
    case useOriginal
    /// Rewrite the same text again, without recognising the audio again (E10-S4).
    case regenerate
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
        case .recognitionFailed(.languageUncertain), .languageUnavailable, .reviewTranslation:
            return languageActions
        case .reviewRewrite(let notice):
            return Self.rewriteReviewActions(notice)
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
        case .editingUnavailable, .rewriterUnavailable, .rewriteFailed:
            return editingActions
        }
    }

    /// Choices for a rewrite review (E10-S4): Regenerate only when trying again can help.
    private static func rewriteReviewActions(_ notice: RewriteNotice?) -> [DictationAction] {
        guard let notice else { return [.insertText, .useOriginal, .regenerate, .copyText, .discard] }
        return notice.isRetryable
            ? [.insertText, .regenerate, .copyText, .discard] : [.insertText, .copyText, .discard]
    }

    /// Choices for language problems and translation review (E9-S2, E9-S3, E9-S5).
    private var languageActions: [DictationAction] {
        switch self {
        case .recognitionFailed(.languageUncertain): SpokenLanguages.all.map { .useLanguage($0.code) } + [.discard]
        case .languageUnavailable: [.chooseLanguage, .discard]
        default: [.insertText, .copyText, .retry, .discard]
        }
    }

    /// Voice-editing issues (E3-S5): nothing was changed, so Discard is safe.
    private var editingActions: [DictationAction] {
        switch self {
        case .editingUnavailable(.editingDisabled), .editingUnavailable(.excludedApp), .rewriterUnavailable:
            [.openContextSettings, .discard]
        case .editingUnavailable(.noAccessibility):
            [.openPermissions, .discard]
        case .rewriteFailed(let error) where error.isRetryable:
            [.retry, .discard]
        default:
            [.discard]
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
    /// A rewrite (or the original, with a reason) waiting for the user's choice
    /// before anything is inserted (E10-S4). Held in memory only.
    case review(DictationReview, engine: RecognitionEngineID?)
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

    /// Rewrites `original` again in the session's style, without recognising
    /// the audio again (E10-S4). Ends in another review.
    func regenerate(
        _ original: String,
        for session: DictationSession,
        updates: @escaping @Sendable (ProcessingUpdate) -> Void
    ) async -> DictationOutcome

    /// Why voice editing can't start for `target`, checked before recording
    /// so the user doesn't speak for nothing; `nil` when it can.
    func editingIssue(for target: ActivationTarget?, language: String) async -> DictationIssue?

    /// Why the chosen language and output can't run, checked before recording
    /// so the user doesn't speak for nothing (E9-S3). `nil` when they can, and
    /// always `nil` for plain English dictation.
    func languageIssue(language: String, output: SpeechOutput, enginePreference: EnginePreference) async
        -> DictationIssue?

}

extension DictationProcessing {
    public func regenerate(
        _ original: String,
        for session: DictationSession,
        updates: @escaping @Sendable (ProcessingUpdate) -> Void
    ) async -> DictationOutcome {
        .cancelled
    }

    public func languageIssue(language: String, output: SpeechOutput, enginePreference: EnginePreference) async
        -> DictationIssue?
    {
        nil
    }

    public func editingIssue(for target: ActivationTarget?, language: String) async -> DictationIssue? {
        .rewriterUnavailable(.unavailable)
    }
}
