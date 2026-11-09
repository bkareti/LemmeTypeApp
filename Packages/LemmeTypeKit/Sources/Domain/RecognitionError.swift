/// Expected recognition failures. Identifiers are stable (see ``LemmeTypeError``).
public enum RecognitionError: LemmeTypeError, Equatable {
    /// The session was cancelled; never shown as a failure.
    case cancelled
    case assetsMissing
    case unsupported(UnsupportedReason)
    /// Speech recognition authorization is denied or not yet given.
    case permissionDenied
    /// The recording could not be read.
    case audioUnreadable
    /// The recording contained no recognisable speech.
    case noSpeechDetected
    /// The recording had a normal length but no sound at all (nothing above the silence
    /// threshold). The microphone, not the speech engine, is the likely cause: it can be
    /// muted, or held by a call or another app. Kept apart from ``noSpeechDetected`` so the
    /// user is told to check the microphone instead of speaking again.
    case silentAudio
    case modelLoadFailed
    /// Automatic detection could not name the language with enough confidence
    /// (E9-S2). The user chooses the language instead of the app guessing.
    case languageUncertain
    /// The framework reported an error; `code` is its numeric code only.
    case engineFailure(code: Int)
    /// The cloud engine could not reach its provider (ADR 0031).
    case cloudOffline
    /// The provider refused the API key.
    case cloudKeyRejected
    /// The provider asked to slow down, and retrying did not help.
    case cloudRateLimited
    /// The account has no credit left.
    case cloudQuotaExhausted
    /// The provider failed, timed out, or answered with something unusable.
    case cloudServiceFailed

    public var identifier: String {
        switch self {
        case .cancelled: "recognition.cancelled"
        case .assetsMissing: "recognition.assets-missing"
        case .unsupported: "recognition.unsupported"
        case .permissionDenied: "recognition.permission-denied"
        case .audioUnreadable: "recognition.audio-unreadable"
        case .noSpeechDetected: "recognition.no-speech"
        case .silentAudio: "recognition.silent-audio"
        case .modelLoadFailed: "recognition.model-load-failed"
        case .languageUncertain: "recognition.language-uncertain"
        case .engineFailure: "recognition.engine-failure"
        case .cloudOffline: "recognition.cloud-offline"
        case .cloudKeyRejected: "recognition.cloud-key-rejected"
        case .cloudRateLimited: "recognition.cloud-rate-limited"
        case .cloudQuotaExhausted: "recognition.cloud-quota-exhausted"
        case .cloudServiceFailed: "recognition.cloud-service-failed"
        }
    }

    /// Whether running the same engine again could succeed without the user
    /// changing anything else.
    public var isRetryable: Bool {
        switch self {
        case .engineFailure, .modelLoadFailed, .audioUnreadable, .cloudOffline, .cloudRateLimited, .cloudServiceFailed:
            true
        case .cancelled, .assetsMissing, .unsupported, .permissionDenied, .noSpeechDetected, .silentAudio,
            .languageUncertain, .cloudKeyRejected, .cloudQuotaExhausted:
            false
        }
    }
}
