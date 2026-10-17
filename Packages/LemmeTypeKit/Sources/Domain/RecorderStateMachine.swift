/// Where a dictation session is. Every state is visible to the user.
public enum RecorderState: Equatable, Sendable {
    case idle
    /// Starting the microphone.
    case preparing
    case recording
    /// Finalising the recording.
    case stopping
    /// Recognising, writing, and delivering the text.
    case processing
    case completed
    case cancelled
    case failed(AudioCaptureError)
    /// Processing stopped and the user must choose what to do (retry, copy,
    /// discard, …). The recording is kept until they decide.
    case needsAttention(DictationIssue)

    /// The microphone may be in use.
    public var isCapturing: Bool {
        self == .preparing || self == .recording || self == .stopping
    }

    /// Finished; the next activation starts a new session.
    public var isFinished: Bool {
        switch self {
        case .completed, .cancelled, .failed, .needsAttention: true
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
    /// Processing needs a decision from the user.
    case processingNeedsAttention(DictationIssue)
    /// The user chose to process the kept recording again.
    case retry
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

    // One case per allowed transition: the table is the specification, so it
    // stays in one place rather than being split to lower its complexity.
    // swiftlint:disable:next cyclomatic_complexity
    public static func transition(from state: RecorderState, on event: RecorderEvent) -> RecorderState? {
        switch (state, event) {
        case (.idle, .activate): .preparing
        case (.preparing, .captureStarted): .recording
        case (.recording, .stopRequested): .stopping
        case (.stopping, .captureFinished): .processing
        case (.processing, .processingFinished): .completed
        // The user resolved an issue themselves (for example Copy Text).
        case (.needsAttention, .processingFinished): .completed
        case (.processing, .processingNeedsAttention(let issue)): .needsAttention(issue)
        // Voice editing is refused before the microphone starts (E3-S5).
        case (.preparing, .processingNeedsAttention(let issue)): .needsAttention(issue)
        case (.needsAttention, .retry): .processing
        case (.preparing, .cancel), (.recording, .cancel), (.processing, .cancel), (.needsAttention, .cancel):
            .cancelled
        case (.preparing, .fail(let error)), (.recording, .fail(let error)),
            (.stopping, .fail(let error)), (.processing, .fail(let error)):
            .failed(error)
        case (let finished, .reset) where finished.isFinished: .idle
        case (let finished, .activate) where finished.isFinished: .preparing
        default: nil
        }
    }
}
