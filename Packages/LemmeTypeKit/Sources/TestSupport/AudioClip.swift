#if DEBUG
    import AVFoundation
    import Domain
    import Foundation

    /// Mono audio in memory for the evaluation harness: loaded from a corpus
    /// file, or generated for edge cases (silence, noise, clipping, very short
    /// and very long input). Every generator and transform is deterministic —
    /// noise comes from a seed — so the same clip is produced on every run.
    ///
    /// Transforms never change what was said, so a derived clip keeps its
    /// source's human reference; generated clips without speech have an empty one.
    public struct AudioClip: Equatable, Sendable {
        public var samples: [Float]
        public let sampleRate: Double

        public init(samples: [Float], sampleRate: Double = AudioCaptureFormat.speech.sampleRate) {
            self.samples = samples
            self.sampleRate = sampleRate
        }

        public var duration: Double { Double(samples.count) / sampleRate }

        private static func frames(_ seconds: Double, at sampleRate: Double) -> Int {
            max(0, Int((seconds * sampleRate).rounded()))
        }

        // MARK: Generated clips

        public static func silence(seconds: Double, sampleRate: Double = AudioCaptureFormat.speech.sampleRate)
            -> AudioClip
        {
            AudioClip(samples: [Float](repeating: 0, count: frames(seconds, at: sampleRate)), sampleRate: sampleRate)
        }

        public static func tone(
            seconds: Double, frequency: Double = 220, amplitude: Float = 0.3,
            sampleRate: Double = AudioCaptureFormat.speech.sampleRate
        ) -> AudioClip {
            AudioClip(
                samples: (0..<frames(seconds, at: sampleRate)).map {
                    amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate))
                }, sampleRate: sampleRate)
        }

        /// Uniform white noise in `-amplitude...amplitude`.
        public static func whiteNoise(
            seconds: Double, amplitude: Float, seed: UInt64, sampleRate: Double = AudioCaptureFormat.speech.sampleRate
        ) -> AudioClip {
            var generator = SeededGenerator(seed: seed)
            return AudioClip(
                samples: (0..<frames(seconds, at: sampleRate)).map { _ in
                    Float.random(in: -1...1, using: &generator) * amplitude
                }, sampleRate: sampleRate)
        }

        // MARK: Transforms

        /// Adds white noise at `snrDecibels` below the clip's mean power. The
        /// benchmark's noisy recordings (E2-S10) are made with this.
        public func withNoise(snrDecibels: Double, seed: UInt64) -> AudioClip {
            var power = 0.0
            for sample in samples { power += Double(sample * sample) }
            let signal = power / Double(max(samples.count, 1))
            // Uniform noise in -a...a has power a²/3.
            let amplitude = Float((signal / pow(10, snrDecibels / 10) * 3).squareRoot())
            var generator = SeededGenerator(seed: seed)
            return AudioClip(
                samples: samples.map { $0 + Float.random(in: -1...1, using: &generator) * amplitude },
                sampleRate: sampleRate)
        }

        /// Amplifies by `gain` and clips to full scale, like an overdriven microphone.
        public func clipped(gain: Float) -> AudioClip {
            AudioClip(samples: samples.map { min(1, max(-1, $0 * gain)) }, sampleRate: sampleRate)
        }

        /// Silence before and after: a late start or a long pause before stopping.
        public func padded(leading: Double = 0, trailing: Double = 0) -> AudioClip {
            let before = [Float](repeating: 0, count: Self.frames(leading, at: sampleRate))
            let after = [Float](repeating: 0, count: Self.frames(trailing, at: sampleRate))
            return AudioClip(samples: before + samples + after, sampleRate: sampleRate)
        }

        /// The first `seconds`. The reference no longer matches unless the cut is in silence.
        public func prefix(seconds: Double) -> AudioClip {
            AudioClip(samples: Array(samples.prefix(Self.frames(seconds, at: sampleRate))), sampleRate: sampleRate)
        }

        /// Plays `factor` times as fast — tempo and pitch together, like a tape
        /// run faster or slower (speed perturbation). Linear interpolation, no
        /// anti-alias filter: meant for factors near 1, such as 0.9 and 1.1.
        public func speed(_ factor: Double) -> AudioClip {
            guard factor > 0, factor != 1, let last = samples.indices.last else { return self }
            let count = Int((Double(samples.count) / factor).rounded())
            var changed: [Float] = []
            changed.reserveCapacity(count)
            for index in 0..<count {
                let position = Double(index) * factor
                let lower = min(Int(position), last)
                let upper = min(lower + 1, last)
                let fraction = Float(position - Double(lower))
                changed.append(samples[lower] + (samples[upper] - samples[lower]) * fraction)
            }
            return AudioClip(samples: changed, sampleRate: sampleRate)
        }

        /// `count` copies with `gap` seconds of silence between them; the
        /// reference is the source's reference `count` times.
        public func repeated(_ count: Int, gap: Double = 0) -> AudioClip {
            let silence = [Float](repeating: 0, count: Self.frames(gap, at: sampleRate))
            var joined: [Float] = []
            joined.reserveCapacity((samples.count + silence.count) * max(count, 0))
            for index in 0..<max(count, 0) {
                if index > 0 { joined += silence }
                joined += samples
            }
            return AudioClip(samples: joined, sampleRate: sampleRate)
        }

        // MARK: Files

        public enum FileError: Error, Equatable {
            case unreadable
            case unwritable
        }

        /// Reads any file AVFoundation can open and mixes it down to mono.
        public static func load(from url: URL) throws -> AudioClip {
            let file: AVAudioFile
            do { file = try AVAudioFile(forReading: url) } catch { throw FileError.unreadable }
            let format = file.processingFormat
            guard file.length > 0 else { return AudioClip(samples: [], sampleRate: format.sampleRate) }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else {
                throw FileError.unreadable
            }
            let channelCount = Int(format.channelCount)
            let scale = 1 / Float(max(channelCount, 1))
            var mono: [Float] = []
            mono.reserveCapacity(Int(file.length))
            // One read returns whole 1,024-frame blocks only; read until the file ends.
            while file.framePosition < file.length {
                do { try file.read(into: buffer) } catch { throw FileError.unreadable }
                let count = Int(buffer.frameLength)
                guard count > 0 else { break }
                guard let channels = buffer.floatChannelData else { throw FileError.unreadable }
                for index in 0..<count {
                    var sum: Float = 0
                    for channel in 0..<channelCount { sum += channels[channel][index] }
                    mono.append(channelCount > 1 ? sum * scale : sum)
                }
            }
            return AudioClip(samples: mono, sampleRate: format.sampleRate)
        }

        /// Writes 32-bit float mono; the container (CAF, WAVE, …) follows the file extension.
        public func write(to url: URL) throws {
            guard
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
            else { throw FileError.unwritable }
            do {
                let file = try AVAudioFile(
                    forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                guard !samples.isEmpty else { return }
                guard
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                    let channel = buffer.floatChannelData?[0]
                else { throw FileError.unwritable }
                buffer.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { source in
                    guard let base = source.baseAddress else { return }
                    channel.update(from: base, count: samples.count)
                }
                try file.write(from: buffer)
            } catch let error as FileError {
                throw error
            } catch {
                throw FileError.unwritable
            }
        }
    }
#endif
