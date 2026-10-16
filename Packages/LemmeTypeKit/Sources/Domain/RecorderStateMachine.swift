/// Where a dictation session is. Every state is visible to the user.
public enum RecorderState: Equatable, Sendable {
    case idle
    /// Starting the microphone.
    case preparing
    case recording
    /// Finalising the recording.
    case stopping
    /// Handing the recording on (transcription arrives in Epic 2).
    case processing
    case completed
    case cancelled
    case failed(AudioCaptureError)

    /// The microphone may be in use.
    public var isCapturing: Bool {
        self == .preparing || self == .recording || self == .stopping
    }

    /// Finished; the next activation starts a new session.
    public var isFinished: Bool {
        switch self {
        case .completed, .cancelled, .failed: true
        default: false
        }
    }
}

public enum RecorderEvent: Equatable, Sendable {
    case activate
    case captureStarted
    case stopRequested
    case captureFinished
    case processingFinished
    case cancel
    case fail(AudioCaptureError)
    /// The finished state has been dismissed.
    case reset
}

/// The recorder's single source of truth. Rejects every transition that is
/// not explicitly allowed, so overlapping or out-of-order events cannot leave
/// the microphone running.
public struct RecorderStateMachine: Sendable {
    public private(set) var state: RecorderState = .idle

    public init() {}

    /// Applies `event` and returns `true`, or returns `false` and leaves the
    /// state unchanged if the transition is not allowed.
    @discardableResult
    public mutating func handle(_ event: RecorderEvent) -> Bool {
        guard let next = Self.transition(from: state, on: event) else { return false }
        state = next
        return true
    }

    public static func transition(from state: RecorderState, on event: RecorderEvent) -> RecorderState? {
        switch (state, event) {
        case (.idle, .activate): .preparing
        case (.preparing, .captureStarted): .recording
        case (.recording, .stopRequested): .stopping
        case (.stopping, .captureFinished): .processing
        case (.processing, .processingFinished): .completed
        case (.preparing, .cancel), (.recording, .cancel), (.processing, .cancel): .cancelled
        case (.preparing, .fail(let error)), (.recording, .fail(let error)),
            (.stopping, .fail(let error)), (.processing, .fail(let error)):
            .failed(error)
        case (let finished, .reset) where finished.isFinished: .idle
        case (let finished, .activate) where finished.isFinished: .preparing
        default: nil
        }
    }
}

/// Receives each finished recording. Epic 1 discards it; Epic 2 transcribes
/// and delivers text to `target`. Implementations must delete the file.
public protocol RecordingConsumer: Sendable {
    func consume(_ recording: RecordedAudio, target: ActivationTarget?) async throws(AudioCaptureError)
}
