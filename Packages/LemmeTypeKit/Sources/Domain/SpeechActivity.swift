/// Cheap, content-free check for whether a recording contains any sound worth
/// sending to a recogniser. Only signal energy is computed; nothing is kept.
public enum SpeechActivity {
    /// Recordings shorter than this are treated as empty.
    public static let minimumDuration = 0.2
    /// Window RMS below this everywhere counts as silence (about −50 dBFS).
    public static let silenceThreshold: Float = 0.003

    /// Whether no 50 ms window of `samples` (at `sampleRate`) rises above
    /// ``silenceThreshold``.
    public static func isSilent(_ samples: [Float], sampleRate: Double = AudioCaptureFormat.speech.sampleRate) -> Bool {
        let window = max(1, Int(sampleRate * 0.05))
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + window)
            var sum: Float = 0
            for sample in samples[index..<end] {
                sum += sample * sample
            }
            if (sum / Float(end - index)).squareRoot() > silenceThreshold {
                return false
            }
            index = end
        }
        return true
    }
}
