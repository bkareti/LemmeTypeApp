#if DEBUG
    import Domain
    import Foundation
    import Synchronization

    /// An audio source that "hears" a recorded clip instead of a microphone, so
    /// corpus speech goes through the real capture service — resampling, level
    /// meter, session file — exactly as live speech would. The test decides how
    /// much of the clip plays and when an interruption or device loss happens;
    /// nothing is timed by a real clock, so runs are deterministic.
    public final class FileAudioSource: AudioSource {
        private struct State {
            var onEvent: (@Sendable (AudioSourceEvent) -> Void)?
            var position = 0
            var startCount = 0
            var stopCount = 0
        }

        private let clip: AudioClip
        private let bufferFrames: Int
        private let state = Mutex(State())

        /// `bufferSeconds` is how much audio each buffer carries, like a hardware callback.
        public init(clip: AudioClip, bufferSeconds: Double = 0.1) {
            self.clip = clip
            bufferFrames = max(1, Int(clip.sampleRate * bufferSeconds))
        }

        public convenience init(contentsOf url: URL, bufferSeconds: Double = 0.1) throws {
            self.init(clip: try AudioClip.load(from: url), bufferSeconds: bufferSeconds)
        }

        public var startCount: Int { state.withLock { $0.startCount } }
        public var stopCount: Int { state.withLock { $0.stopCount } }
        public var isRunning: Bool { state.withLock { $0.onEvent != nil } }
        /// Seconds of the clip already delivered.
        public var playedSeconds: Double { Double(state.withLock { $0.position }) / clip.sampleRate }
        public var isFinished: Bool { state.withLock { $0.position >= clip.samples.count } }

        /// Starts at the beginning of the clip every time.
        public func start(
            input: AudioInputSelection,
            onEvent: @escaping @Sendable (AudioSourceEvent) -> Void
        ) throws(AudioCaptureError) -> AudioSourceStart {
            state.withLock {
                $0.startCount += 1
                $0.onEvent = onEvent
                $0.position = 0
            }
            return AudioSourceStart(usedSystemDefaultFallback: false)
        }

        public func stop() {
            state.withLock {
                $0.stopCount += 1
                $0.onEvent = nil
            }
        }

        /// Delivers the clip from where it stopped up to `seconds` into it (the
        /// end when `nil`), in buffers of the configured size. Does nothing
        /// while stopped.
        public func play(upTo seconds: Double? = nil) {
            let end =
                seconds.map { min(clip.samples.count, Int(($0 * clip.sampleRate).rounded())) }
                ?? clip.samples.count
            while let (onEvent, range) = nextBuffer(endingBy: end) {
                onEvent(.buffer(Array(clip.samples[range]), sampleRate: clip.sampleRate))
            }
        }

        /// Delivers an event, such as an interruption or device loss, if running.
        public func emit(_ event: AudioSourceEvent) {
            state.withLock { $0.onEvent }?(event)
        }

        /// Claims the next buffer under the lock; the callback runs outside it.
        private func nextBuffer(endingBy end: Int) -> ((@Sendable (AudioSourceEvent) -> Void), Range<Int>)? {
            state.withLock { state in
                guard let onEvent = state.onEvent, state.position < end else { return nil }
                let range = state.position..<min(end, state.position + bufferFrames)
                state.position = range.upperBound
                return (onEvent, range)
            }
        }
    }
#endif
