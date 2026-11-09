import Foundation
import Testing

@testable import Recognition

/// E11-S2: where a long recording is cut.
struct SpeechSplitterTests {
    static let rate = 16_000.0

    static func tone(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * rate)).map { Float(sin(2 * Double.pi * 220 * Double($0) / rate)) * 0.3 }
    }

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * rate))
    }

    private func ranges(_ samples: [Float], maximum: Double = 30) -> [Range<Int>] {
        SpeechSplitter.ranges(of: samples, sampleRate: Self.rate, maximumSeconds: maximum)
    }

    /// Every sample once, in order, and no part over the limit.
    private func expectComplete(_ parts: [Range<Int>], count: Int, maximum: Double = 30) {
        #expect(parts.first?.lowerBound == 0)
        #expect(parts.last?.upperBound == count)
        for (left, right) in zip(parts, parts.dropFirst()) { #expect(left.upperBound == right.lowerBound) }
        for part in parts { #expect(part.count <= Int(maximum * Self.rate) && !part.isEmpty) }
    }

    @Test func aRecordingAtTheLimitIsOnePart() {
        let exact = Self.tone(30)
        #expect(ranges(exact) == [0..<exact.count])
        let short = Self.tone(5)
        #expect(ranges(short) == [0..<short.count])
    }

    @Test func nothingBecomesNoParts() {
        #expect(ranges([]).isEmpty)
    }

    @Test func withoutAPauseItCutsAtTheLimit() {
        let samples = Self.tone(70)
        let parts = ranges(samples)
        expectComplete(parts, count: samples.count)
        #expect(parts.count == 3)
        #expect(parts[0].count == Int(30 * Self.rate))
    }

    @Test func itCutsInsideAPause() {
        let samples = Self.tone(24) + Self.silence(1) + Self.tone(24)
        let parts = ranges(samples)
        expectComplete(parts, count: samples.count)
        #expect(parts.count == 2)
        let pause = Int(24 * Self.rate)...Int(25 * Self.rate)
        #expect(pause.contains(parts[0].upperBound))
    }

    @Test func itPrefersThePauseNearestTwentyFiveSeconds() {
        let samples =
            Self.tone(16) + Self.silence(0.5) + Self.tone(8) + Self.silence(0.5) + Self.tone(4) + Self.silence(0.5)
            + Self.tone(20)
        let parts = ranges(samples)
        expectComplete(parts, count: samples.count)
        let cut = Double(parts[0].upperBound) / Self.rate
        #expect(cut > 24.5 && cut < 25)
    }

    @Test func aGapTooShortToBeAPauseIsIgnored() {
        let samples = Self.tone(24) + Self.silence(0.1) + Self.tone(24)
        #expect(ranges(samples)[0].count == Int(30 * Self.rate))
    }

    @Test func quietBackgroundNoiseStillCountsAsAPause() {
        let noise = [Float](repeating: 0.01, count: Int(Self.rate))
        let samples = Self.tone(24) + noise + Self.tone(24)
        let cut = ranges(samples)[0].upperBound
        #expect((Int(24 * Self.rate)...Int(25 * Self.rate)).contains(cut))
    }

    @Test func noTinyFragmentIsLeftAtTheEnd() {
        let samples = Self.tone(30.2)
        let parts = ranges(samples)
        expectComplete(parts, count: samples.count)
        #expect(parts.count == 2)
        #expect(parts[1].count == Int(Self.rate))
    }

    @Test func aDifferentProviderLimitIsRespected() {
        let samples = Self.tone(130)
        let parts = ranges(samples, maximum: 60)
        expectComplete(parts, count: samples.count, maximum: 60)
        #expect(parts.count == 3)
    }
}
