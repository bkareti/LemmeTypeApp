import Domain
import Foundation
import TestSupport
import Testing

@testable import Recognition

/// ADR 0028, #135: noise and tones end as "No speech was detected".
struct NoSpeechGateTests {
    private let fixtures = RecordingFixtures()

    private static func segment(logProbability: Float, tokens: Int = 4) -> WhisperSegment {
        WhisperSegment(
            text: "Thank you.", start: 0, duration: 1, tokenCount: tokens, averageLogProbability: logProbability)
    }

    @Test func onlyEveryWindowBeingAlmostCertainSkipsDecoding() {
        #expect(NoSpeechGate.skipsDecoding([0.9]))
        #expect(NoSpeechGate.skipsDecoding([0.77, 0.96]))
        #expect(!NoSpeechGate.skipsDecoding([0.74]))
        // A long dictation with one quiet window still has speech in it.
        #expect(!NoSpeechGate.skipsDecoding([0.9, 0.2]))
        #expect(!NoSpeechGate.skipsDecoding([]))
    }

    @Test func probableNoSpeechDropsOnlyUnsureText() {
        let unsure = [Self.segment(logProbability: -2.5)]
        let sure = [Self.segment(logProbability: -0.3)]
        #expect(NoSpeechGate.dropsDecoded(unsure, windows: [0.65]))
        #expect(NoSpeechGate.dropsDecoded([], windows: [0.65]))
        #expect(!NoSpeechGate.dropsDecoded(sure, windows: [0.65]))
        #expect(!NoSpeechGate.dropsDecoded(unsure, windows: [0.4]))
        #expect(!NoSpeechGate.dropsDecoded(unsure, windows: [0.65, 0.3]))
        #expect(!NoSpeechGate.dropsDecoded(unsure, windows: []))
    }

    @Test func theLogProbabilityIsWeightedByTokens() {
        // 1 token at -5 and 9 at -0.5 average -0.95: sure enough to keep.
        let segments = [Self.segment(logProbability: -5, tokens: 1), Self.segment(logProbability: -0.5, tokens: 9)]
        #expect(!NoSpeechGate.dropsDecoded(segments, windows: [0.7]))
    }

    @Test func certainNoSpeechNeverReachesTheDecoder() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime(noSpeech: [0.9])
        let engine = makeEngine(runtime)
        await #expect(throws: RecognitionError.noSpeechDetected) {
            try await engine.recognize(try fixtures.make(.tone(seconds: 1.5))) { _ in }
        }
        #expect(runtime.receivedInferences.isEmpty)
    }

    @Test func probableNoSpeechWithUnsureTextIsNoSpeech() async throws {
        defer { fixtures.removeAll() }
        let engine = makeEngine(
            FakeWhisperRuntime(segments: [Self.segment(logProbability: -2)], noSpeech: [0.7]))
        await #expect(throws: RecognitionError.noSpeechDetected) {
            try await engine.recognize(try fixtures.make(.tone(seconds: 1.5))) { _ in }
        }
    }

    @Test func probableNoSpeechWithSureTextIsKept() async throws {
        defer { fixtures.removeAll() }
        let engine = makeEngine(
            FakeWhisperRuntime(segments: [Self.segment(logProbability: -0.2)], noSpeech: [0.7]))
        let transcript = try await engine.recognize(try fixtures.make(.tone(seconds: 1.5))) { _ in }
        #expect(transcript.text == "Thank you.")
    }

    @Test func theShippedDecodingSuppressesNonSpeechTokensAndKeepsTheFallback() {
        let decoding = WhisperDecoding()
        #expect(decoding.suppressesNonSpeechTokens)
        #expect(decoding.temperatureIncrement > 0)
        #expect(decoding.bestOf == 5)
        #expect(decoding.beamSize == nil)
    }

    private func makeEngine(_ runtime: FakeWhisperRuntime) -> WhisperEngine {
        WhisperEngine(
            assets: FakeModelAssetManager(installed: [.whisperBaseEnglish]),
            hardware: HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 16 << 30), runtime: runtime)
    }
}
