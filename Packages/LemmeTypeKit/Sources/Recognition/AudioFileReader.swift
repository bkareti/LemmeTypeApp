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
        guard file.length > 0 else { return [] }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw .audioUnreadable
        }
        // One read returns whole 1,024-frame blocks only, which would drop up
        // to 64 ms from the end of the dictation; read until the file ends.
        var samples: [Float] = []
        samples.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            do {
                try file.read(into: buffer)
            } catch {
                throw .audioUnreadable
            }
            guard buffer.frameLength > 0 else { break }
            guard let channel = buffer.floatChannelData?[0] else { throw .audioUnreadable }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        return samples
    }

    /// About 4 s of speech per read.
    private static let chunkFrames: AVAudioFrameCount = 65_536
}
