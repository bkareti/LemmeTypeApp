/// Decides that a recording has no speech from Whisper's own no-speech
/// probability, so noise and tones end as "No speech was detected" instead
/// of invented text (ADR 0028, #135). Pure.
///
/// The probability is read per 30-second window, right after
/// start-of-transcript (``WhisperModel/noSpeechProbabilities(_:threads:)``).
/// Every window must agree, so one quiet stretch in a long dictation never
/// drops the rest. Measured on 2026-11-03 (Whisper Small, English and
/// multilingual): noise and tones 0.77–0.96; English speech at most 0.21,
/// Hindi speech at most 0.42 in a first window. Proposed until the quality
/// thresholds are approved.
enum NoSpeechGate {
    /// From here the recording is skipped without decoding.
    static let certain: Float = 0.75
    /// From here the decoded text is dropped when Whisper was unsure of it too.
    static let likely: Float = 0.6
    /// Whisper's own "the decode failed" line for the mean token log probability.
    static let unsureLogProbability: Float = -1

    /// Before decoding: every window is almost certainly without speech.
    static func skipsDecoding(_ windows: [Float]) -> Bool {
        !windows.isEmpty && windows.allSatisfy { $0 >= certain }
    }

    /// After decoding: every window is probably without speech and the text
    /// that came out is unsure (or there is none).
    static func dropsDecoded(_ segments: [WhisperSegment], windows: [Float]) -> Bool {
        guard !windows.isEmpty, windows.allSatisfy({ $0 >= likely }) else { return false }
        let tokens = segments.reduce(0) { $0 + $1.tokenCount }
        guard tokens > 0 else { return true }
        let logProbability = segments.reduce(Float(0)) { $0 + $1.averageLogProbability * Float($1.tokenCount) }
        return logProbability / Float(tokens) < unsureLogProbability
    }
}
