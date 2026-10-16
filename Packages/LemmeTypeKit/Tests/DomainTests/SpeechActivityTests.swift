import Domain
import Foundation
import TestSupport
import Testing

struct SpeechActivityTests {
    @Test func silenceAndEmptyAreSilent() {
        #expect(SpeechActivity.isSilent([]))
        #expect(SpeechActivity.isSilent([Float](repeating: 0, count: 16_000)))
        #expect(SpeechActivity.isSilent([Float](repeating: 0.001, count: 16_000)))
    }

    @Test func aShortBurstIsNotSilent() {
        var samples = [Float](repeating: 0, count: 16_000)
        for index in 8_000..<8_800 {
            samples[index] = Float(sin(Double(index) / 4)) * 0.2
        }
        #expect(!SpeechActivity.isSilent(samples))
    }

    @Test func fakeSpeechAuthorizerPromptsOnlyOnce() async {
        let authorizer = FakeSpeechAuthorizer(status: .notRequested, answer: .denied)
        #expect(await authorizer.requestAuthorization() == .denied)
        #expect(await authorizer.requestAuthorization() == .denied)
        #expect(authorizer.requestCount == 1)
    }
}
