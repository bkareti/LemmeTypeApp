#if DEBUG
    /// A deterministic change to a recording that keeps what was said, so the
    /// derived run inherits the recording's human reference: background noise
    /// at a set SNR, an overdriven microphone, a late start and a long pause, a
    /// faster or slower speaker, or a long dictation made of repeats.
    public struct CorpusVariant: Codable, Equatable, Sendable {
        public enum Transform: String, Codable, Equatable, Sendable {
            case noise
            case clip
            case pad
            /// Tempo and pitch together, like a tape played faster or slower.
            case speed
            /// The recording `count` times with `gap` seconds between; the reference repeats too.
            case `repeat`
        }

        public let id: String
        public let transform: Transform
        public let snrDecibels: Double?
        public let seed: UInt64?
        public let gain: Float?
        public let leading: Double?
        public let trailing: Double?
        public let factor: Double?
        public let count: Int?
        public let gap: Double?
        /// Apply to every n-th recording in manifest order (1, or absent: all of them).
        public let sampleEvery: Int?

        public init(
            id: String, transform: Transform, snrDecibels: Double? = nil, seed: UInt64? = nil, gain: Float? = nil,
            leading: Double? = nil, trailing: Double? = nil, factor: Double? = nil, count: Int? = nil,
            gap: Double? = nil, sampleEvery: Int? = nil
        ) {
            self.id = id
            self.transform = transform
            self.snrDecibels = snrDecibels
            self.seed = seed
            self.gain = gain
            self.leading = leading
            self.trailing = trailing
            self.factor = factor
            self.count = count
            self.gap = gap
            self.sampleEvery = sampleEvery
        }

        var samplingStride: Int { max(1, sampleEvery ?? 1) }

        func problems() -> [String] {
            var found: [String] = []
            if let sampleEvery, sampleEvery < 1 { found.append("sampleEvery must be at least 1") }
            if let problem = transformProblem() { found.append(problem) }
            return found
        }

        private func transformProblem() -> String? {
            switch transform {
            case .noise:
                snrDecibels == nil || seed == nil ? "noise needs snrDecibels and seed" : nil
            case .clip:
                (gain ?? 0) <= 1 ? "clip needs a gain above 1" : nil
            case .pad:
                (leading ?? 0) < 0 || (trailing ?? 0) < 0 || (leading ?? 0) + (trailing ?? 0) == 0
                    ? "pad needs a positive leading or trailing" : nil
            case .speed:
                !(0.5...2).contains(factor ?? 0) || factor == 1 ? "speed needs a factor in 0.5…2, not 1" : nil
            case .repeat:
                !(2...10).contains(count ?? 0) ? "repeat needs a count in 2…10" : nil
            }
        }

        func apply(to clip: AudioClip) -> AudioClip {
            switch transform {
            case .noise: clip.withNoise(snrDecibels: snrDecibels ?? 20, seed: seed ?? 1)
            case .clip: clip.clipped(gain: gain ?? 1)
            case .pad: clip.padded(leading: leading ?? 0, trailing: trailing ?? 0)
            case .speed: clip.speed(factor ?? 1)
            case .repeat: clip.repeated(count ?? 1, gap: gap ?? 0)
            }
        }

        func reference(for text: String) -> String {
            guard transform == .repeat, !text.isEmpty else { return text }
            return Array(repeating: text, count: max(count ?? 1, 1)).joined(separator: " ")
        }
    }
#endif
