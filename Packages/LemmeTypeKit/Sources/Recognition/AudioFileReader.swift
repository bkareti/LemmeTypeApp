import AVFoundation
import Domain

/// Reads a session recording into memory as 16 kHz mono float samples.
/// The samples live only as long as the caller holds them.
enum AudioFileReader {
    static func readSamples(from url: URL) throws(RecognitionError) -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw .audioUnreadable
        }
        let format = file.processingFormat
        guard format.sampleRate == AudioCaptureFormat.speech.sampleRate, format.channelCount == 1 else {
            throw .audioUnreadable
        }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { return [] }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw .audioUnreadable
        }
        do {
            try file.read(into: buffer)
        } catch {
            throw .audioUnreadable
        }
        guard let channel = buffer.floatChannelData?[0] else { throw .audioUnreadable }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
