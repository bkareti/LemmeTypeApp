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
    case modelLoadFailed
    /// The framework reported an error; `code` is its numeric code only.
    case engineFailure(code: Int)

    public var identifier: String {
        switch self {
        case .cancelled: "recognition.cancelled"
        case .assetsMissing: "recognition.assets-missing"
        case .unsupported: "recognition.unsupported"
        case .permissionDenied: "recognition.permission-denied"
        case .audioUnreadable: "recognition.audio-unreadable"
        case .noSpeechDetected: "recognition.no-speech"
        case .modelLoadFailed: "recognition.model-load-failed"
        case .engineFailure: "recognition.engine-failure"
        }
    }

    /// Whether running the same engine again could succeed without the user
    /// changing anything else.
    public var isRetryable: Bool {
        switch self {
        case .engineFailure, .modelLoadFailed, .audioUnreadable: true
        case .cancelled, .assetsMissing, .unsupported, .permissionDenied, .noSpeechDetected: false
        }
    }
}
