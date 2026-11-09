import Domain

/// Cuts a long recording into parts one provider request can take (E11-S2).
/// Cuts fall inside a pause when there is one, because a word cut in half is
/// usually a word lost. Works on signal energy only; nothing is kept.
enum SpeechSplitter {
    /// Shorter gaps than this happen inside a phrase.
    static let minimumPauseSeconds = 0.25
    /// Nothing shorter is left as a final part: a fragment gives the provider nothing to work with.
    static let minimumPartSeconds = 1.0
    static let frameSeconds = 0.05
    /// How far below the loudest frame counts as quiet: about −25 dB.
    static let quietFraction: Float = 0.056

    /// Consecutive ranges that cover every sample once. One range when the recording fits.
    static func ranges(
        of samples: [Float], sampleRate: Double = AudioCaptureFormat.speech.sampleRate, maximumSeconds: Double
    ) -> [Range<Int>] {
        let limit = Int(maximumSeconds * sampleRate)
        guard limit > 0, samples.count > limit else { return samples.isEmpty ? [] : [0..<samples.count] }
        let pauses = pauseMidpoints(in: samples, sampleRate: sampleRate)
        let target = limit * 5 / 6
        let shortest = Int(minimumPartSeconds * sampleRate)

        var ranges: [Range<Int>] = []
        var start = 0
        while samples.count - start > limit {
            let window = (start + limit / 2)...(start + limit)
            let wanted = start + target
            let pause = pauses.filter(window.contains).min { abs($0 - wanted) < abs($1 - wanted) }
            var cut = pause ?? (start + limit)
            if samples.count - cut < shortest { cut = max(start + 1, samples.count - shortest) }
            ranges.append(start..<cut)
            start = cut
        }
        ranges.append(start..<samples.count)
        return ranges
    }

    /// The middle of every quiet stretch long enough to be a pause.
    private static func pauseMidpoints(in samples: [Float], sampleRate: Double) -> [Int] {
        let frameLength = max(1, Int(frameSeconds * sampleRate))
        let levels = stride(from: 0, to: samples.count, by: frameLength).map { start -> Float in
            let frame = samples[start..<min(samples.count, start + frameLength)]
            return (frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)).squareRoot()
        }
        let quiet = max(SpeechActivity.silenceThreshold, (levels.max() ?? 0) * quietFraction)
        let shortestRun = Int((minimumPauseSeconds / frameSeconds).rounded())

        var midpoints: [Int] = []
        var runStart: Int?
        for (index, level) in levels.enumerated() + [(levels.count, Float.infinity)] {
            if level <= quiet {
                if runStart == nil { runStart = index }
            } else if let first = runStart {
                if index - first >= shortestRun { midpoints.append((first + index) / 2 * frameLength) }
                runStart = nil
            }
        }
        return midpoints
    }
}
