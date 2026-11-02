import Domain
import Foundation
import Testing

@testable import Recognition

/// Engines get every sample of the recording. A single `AVAudioFile` read
/// returns whole 1,024-frame blocks only, which dropped the end of the
/// dictation (40 ms of a 1 s recording) before the evaluation harness caught it.
struct AudioFileReaderTests {
    @Test(arguments: [0.5, 1.0, 5.0, 30.0])
    func readsEverySampleOfTheRecording(seconds: Double) throws {
        let fixtures = RecordingFixtures()
        defer { fixtures.removeAll() }
        let request = try fixtures.make(.tone(seconds: seconds))

        let samples = try AudioFileReader.readSamples(from: request.audio.fileURL)

        #expect(samples.count == Int(seconds * AudioCaptureFormat.speech.sampleRate))
    }

    @Test func anEmptyRecordingHasNoSamples() throws {
        let fixtures = RecordingFixtures()
        defer { fixtures.removeAll() }
        let request = try fixtures.make(.empty)

        #expect(try AudioFileReader.readSamples(from: request.audio.fileURL).isEmpty)
    }
}
