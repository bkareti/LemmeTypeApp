import AVFoundation
import Domain
import Foundation
import Testing

/// Writes speech-format recordings for engine tests into a temporary
/// directory with the `LemmeTypeTests-` prefix (checked by `make privacy-check`).
struct RecordingFixtures {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-Recognition-\(UUID().uuidString)", isDirectory: true)

    enum Content {
        case empty
        case silence(seconds: Double)
        /// A 220 Hz tone standing in for speech energy (fake backends do the "recognition").
        case tone(seconds: Double)
    }

    func make(_ content: Content, language: String = "en-US") throws -> RecognitionRequest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).caf")
        let rate = AudioCaptureFormat.speech.sampleRate
        let samples: [Float]
        switch content {
        case .empty:
            samples = []
        case .silence(let seconds):
            samples = [Float](repeating: 0, count: Int(seconds * rate))
        case .tone(let seconds):
            samples = (0..<Int(seconds * rate)).map { Float(sin(2 * Double.pi * 220 * Double($0) / rate)) * 0.3 }
        }
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false))
        let file = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        if !samples.isEmpty {
            let buffer = try #require(
                AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
            buffer.frameLength = AVAudioFrameCount(samples.count)
            let channel = try #require(buffer.floatChannelData?[0])
            for (index, sample) in samples.enumerated() {
                channel[index] = sample
            }
            try file.write(from: buffer)
        }
        return RecognitionRequest(
            audio: RecordedAudio(fileURL: url, duration: Double(samples.count) / rate, format: .speech),
            language: language)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
