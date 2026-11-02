import AVFoundation
import Domain

/// The microphone tap shared by the macOS and iOS audio sources: it downmixes
/// each input buffer to mono and hands it to the capture service.
enum MonoInputTap {
    /// Downmixes every input buffer to mono and forwards it.
    static func install(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        onEvent: @escaping @Sendable (AudioSourceEvent) -> Void
    ) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: frameCount)
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for frame in 0..<frameCount {
                    mono[frame] += samples[frame]
                }
            }
            if channelCount > 1 {
                let scale = 1 / Float(channelCount)
                for frame in 0..<frameCount {
                    mono[frame] *= scale
                }
            }
            onEvent(.buffer(mono, sampleRate: buffer.format.sampleRate))
        }
    }
}
