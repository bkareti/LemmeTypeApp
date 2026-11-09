import Domain
import Foundation
import Testing

@testable import Recognition

/// The WAV the engine uploads, and the opt-in check against the real service.
struct WAVEncoderTests {
    private func little32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    private func sample(_ data: Data, at index: Int) -> Int16 {
        let low = UInt16(data[44 + index * 2])
        let high = UInt16(data[44 + index * 2 + 1])
        return Int16(bitPattern: high << 8 | low)
    }

    @Test func writesACompleteSixteenBitMonoHeader() {
        let data = WAVEncoder.encode([0, 0.5, -0.5])
        #expect(data.count == 44 + 6)
        #expect(data.prefix(4) == Data("RIFF".utf8))
        #expect(data[8..<16] == Data("WAVEfmt ".utf8))
        #expect(little32(data, at: 4) == 36 + 6)
        #expect(data[22] == 1, "mono")
        #expect(little32(data, at: 24) == 16_000)
        #expect(little32(data, at: 28) == 32_000)
        #expect(data[34] == 16, "bits per sample")
        #expect(data[36..<40] == Data("data".utf8))
        #expect(little32(data, at: 40) == 6)
    }

    @Test func clampsOutOfRangeAndNonFiniteSamples() {
        let data = WAVEncoder.encode([2, -2, .nan, .infinity])
        #expect(sample(data, at: 0) == Int16.max)
        #expect(sample(data, at: 1) == -Int16.max)
        #expect(sample(data, at: 2) == 0)
        #expect(sample(data, at: 3) == 0)
    }
}

/// Opt-in: `LEMMETYPE_REAL_CLOUD=1 SARVAM_API_KEY=… LEMMETYPE_REAL_CLOUD_AUDIO=<16 kHz mono Telugu file>`.
/// Uploads that file to Sarvam. Never runs on CI.
struct CloudSpeechRealServiceTests {
    struct EnvironmentKey: CloudCredentialProviding {
        func credential(for provider: CloudSpeechProviderID) async -> CloudCredential? {
            ProcessInfo.processInfo.environment["SARVAM_API_KEY"].map(CloudCredential.init(secret:))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LEMMETYPE_REAL_CLOUD"] == "1"))
    func sarvamTranscribesARealRecording() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LEMMETYPE_REAL_CLOUD_AUDIO"])
        let provider = SarvamProvider()
        let engine = CloudSpeechEngine(
            provider: provider, transport: URLSessionCloudSpeechTransport(allowedHost: provider.host),
            credentials: EnvironmentKey())
        let url = URL(fileURLWithPath: path)
        let seconds = Double(try AudioFileReader.readSamples(from: url).count) / AudioCaptureFormat.speech.sampleRate
        let audio = RecordedAudio(fileURL: url, duration: seconds, format: .speech)
        let transcript = try await engine.recognize(RecognitionRequest(audio: audio, language: "te")) { _ in }
        #expect(!transcript.text.isEmpty)
    }
}
