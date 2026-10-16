import Foundation

/// A span of recognised text. Timing and confidence are optional because not
/// every engine provides them (see ``EngineCapabilities``).
public struct TranscriptSegment: Equatable, Sendable {
    public let text: String
    /// Offset from the start of the recording.
    public let start: TimeInterval?
    public let duration: TimeInterval?
    /// 0...1 when the engine reports it.
    public let confidence: Double?

    public init(text: String, start: TimeInterval? = nil, duration: TimeInterval? = nil, confidence: Double? = nil) {
        self.text = text
        self.start = start
        self.duration = duration
        self.confidence = confidence
    }
}

/// The final result of one recognition. Contains dictated text: it is held in
/// memory for delivery only and is never logged, persisted, or put in
/// diagnostics (use ``metrics`` for that).
public struct Transcript: Equatable, Sendable {
    public let text: String
    public let segments: [TranscriptSegment]
    public let engine: RecognitionEngineID
    /// BCP 47 language the engine recognised.
    public let language: String
    /// Length of the recording.
    public let audioDuration: TimeInterval
    /// Time the engine spent recognising.
    public let processingDuration: TimeInterval

    public init(
        text: String,
        segments: [TranscriptSegment] = [],
        engine: RecognitionEngineID,
        language: String,
        audioDuration: TimeInterval,
        processingDuration: TimeInterval
    ) {
        self.text = text
        self.segments = segments
        self.engine = engine
        self.language = language
        self.audioDuration = audioDuration
        self.processingDuration = processingDuration
    }

    /// Content-free facts that may be recorded in diagnostics.
    public var metrics: TranscriptMetrics {
        TranscriptMetrics(
            engine: engine,
            audioDuration: audioDuration,
            processingDuration: processingDuration,
            segmentCount: segments.count,
            isEmpty: text.allSatisfy(\.isWhitespace)
        )
    }
}

/// Diagnostics-safe summary of a ``Transcript``.
public struct TranscriptMetrics: Equatable, Sendable {
    public let engine: RecognitionEngineID
    public let audioDuration: TimeInterval
    public let processingDuration: TimeInterval
    public let segmentCount: Int
    public let isEmpty: Bool
}
