import AVFoundation
import Domain

/// Converts mono float audio at any device rate to ``AudioCaptureFormat/speech``.
/// Stateful: keeps filter history between buffers so a session resamples
/// seamlessly. One instance per session and input rate.
final class SpeechResampler {
    let inputSampleRate: Double
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    fileprivate var outputFormatForFlush: AVAudioFormat { outputFormat }
    fileprivate let converter: AVAudioConverter?

    init(inputSampleRate: Double) throws(AudioCaptureError) {
        guard
            let input = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: inputSampleRate, channels: 1, interleaved: false),
            let output = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: AudioCaptureFormat.speech.sampleRate, channels: 1,
                interleaved: false)
        else { throw .engineFailure(code: -1) }
        self.inputSampleRate = inputSampleRate
        self.inputFormat = input
        self.outputFormat = output
        if inputSampleRate == AudioCaptureFormat.speech.sampleRate {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: input, to: output) else { throw .engineFailure(code: -2) }
            self.converter = converter
        }
    }

    func process(_ samples: [Float]) -> [Float] {
        guard let converter, !samples.isEmpty else { return samples }
        guard
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
            let inputChannel = inputBuffer.floatChannelData?[0]
        else { return [] }
        inputBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            inputChannel.update(from: base, count: samples.count)
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }

        let feed = SingleBufferFeed(buffer: inputBuffer)
        var error: NSError?
        _ = converter.convert(to: outputBuffer, error: &error) { _, status in
            feed.next(status: status)
        }
        guard error == nil, let output = outputBuffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: output, count: Int(outputBuffer.frameLength)))
    }
}

extension SpeechResampler {
    /// Returns the samples still held in the converter's filter (≈16 ms at
    /// 48 kHz). Call once when the session stops so the tail isn't lost.
    func flush() -> [Float] {
        guard let converter,
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormatForFlush, frameCapacity: 4096)
        else { return [] }
        var error: NSError?
        _ = converter.convert(to: outputBuffer, error: &error) { _, status in
            status.pointee = .endOfStream
            return nil
        }
        guard error == nil, let output = outputBuffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: output, count: Int(outputBuffer.frameLength)))
    }
}

/// Hands the converter one buffer, then reports "no data now" so the
/// converter keeps its state for the next call instead of flushing.
private final class SingleBufferFeed: @unchecked Sendable {
    // Only touched synchronously inside AVAudioConverter.convert on the caller's thread.
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
