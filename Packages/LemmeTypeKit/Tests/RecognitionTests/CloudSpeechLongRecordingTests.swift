import Domain
import Foundation
import Recognition
import Synchronization
import TestSupport
import Testing

/// E11-S2: recordings longer than one provider request.
struct CloudSpeechLongRecordingTests {
    let harness = CloudSpeechEngineTests()

    private func answer(_ text: String) -> FakeCloudSpeechTransport.Step {
        .respond(status: 200, body: Data(#"{"transcript":"\#(text)"}"#.utf8))
    }

    @Test func aRecordingAtTheLimitIsOneRequest() async throws {
        defer { harness.fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([CloudSpeechEngineTests.answered])
        _ = try await harness.engine(transport).recognize(try harness.tone(seconds: 30)) { _ in }
        #expect(transport.requests.count == 1)
    }

    @Test func partsAreSentInOrderAndTheTextIsJoined() async throws {
        defer { harness.fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([answer("one"), answer("two"), answer("three")])
        let transcript = try await harness.engine(transport).recognize(try harness.tone(seconds: 70)) { _ in }
        #expect(transcript.text == "one two three")
        #expect(transport.requests.count == 3)
        #expect(abs(transcript.audioDuration - 70) < 0.5)
    }

    @Test func noAudioIsLostOrSentTwice() async throws {
        defer { harness.fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([.respond(status: 200, body: Data("text:part".utf8))])
        let engine = CloudSpeechEngine(
            provider: ExampleCloudProvider(), transport: transport, credentials: FakeCloudCredentials())
        let request = try harness.tone(seconds: 130)
        _ = try await engine.recognize(request) { _ in }
        #expect(transport.requests.count == 3, "this provider allows 60 seconds per request")
        let sentSamples = transport.requests.reduce(0) { $0 + ($1.body.count - 44) / 2 }
        #expect(sentSamples == Int(130 * AudioCaptureFormat.speech.sampleRate))
    }

    @Test func progressReportsPartsFinished() async throws {
        defer { harness.fixtures.removeAll() }
        let seen = Mutex<[RecognitionUpdate]>([])
        let transport = FakeCloudSpeechTransport([CloudSpeechEngineTests.answered])
        let engine = harness.engine(transport)
        let request = try harness.tone(seconds: 70)
        _ = try await engine.recognize(request) { update in
            seen.withLock { $0.append(update) }
        }
        let fractions = seen.withLock { $0 }.compactMap { update -> Double? in
            if case .progress(let fraction) = update { return fraction }
            return nil
        }
        #expect(fractions.count == 3)
        #expect(fractions.last == 1)
        #expect(fractions == fractions.sorted())
    }

    @Test func aFailedPartDeliversNoPartialTextAndKeepsTheRecording() async throws {
        defer { harness.fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([answer("one"), .fail(.offline)])
        let request = try harness.tone(seconds: 70)
        await #expect(throws: RecognitionError.cloudOffline) {
            try await harness.engine(transport).recognize(request) { _ in }
        }
        #expect(transport.requests.count == 2, "nothing more is sent after a failure")
        #expect(FileManager.default.fileExists(atPath: request.audio.fileURL.path))
    }

    @Test func aRetriedPartIsNotAnsweredTwice() async throws {
        defer { harness.fixtures.removeAll() }
        let clock = ManualClock()
        let transport = FakeCloudSpeechTransport([
            answer("one"), CloudSpeechEngineTests.limited, answer("two"), answer("three"),
        ])
        let result = await harness.runAdvancing(
            harness.engine(transport, clock: clock), try harness.tone(seconds: 70), clock: clock)
        #expect((try? result.get())?.text == "one two three")
        #expect(transport.requests.count == 4)
    }

    @Test func cancellingStopsTheRemainingParts() async throws {
        defer { harness.fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([answer("one"), .hang])
        let engine = harness.engine(transport)
        let request = try harness.tone(seconds: 70)
        let task = Task { await CloudSpeechEngineTests.outcome(engine, request) }
        while transport.requests.count < 2 { await Task.yield() }
        task.cancel()
        #expect(harness.failure(await task.value) == .cancelled)
        #expect(transport.requests.count == 2)
    }

    @Test func aSilentStretchIsNotUploaded() async throws {
        defer { harness.fixtures.removeAll() }
        let rate = AudioCaptureFormat.speech.sampleRate
        let tone = (0..<Int(20 * rate)).map { Float(sin(2 * Double.pi * 220 * Double($0) / rate)) * 0.3 }
        let silence = [Float](repeating: 0, count: Int(40 * rate))
        let transport = FakeCloudSpeechTransport([CloudSpeechEngineTests.answered])
        let request = try harness.fixtures.make(.samples(tone + silence + tone), language: "te")
        _ = try await harness.engine(transport).recognize(request) { _ in }
        let sentSeconds = Double(transport.requests.reduce(0) { $0 + ($1.body.count - 44) / 2 }) / rate
        #expect(sentSeconds < 80)
        #expect(transport.requests.count >= 2)
    }

    @Test func partsLeaveNoExtraFiles() async throws {
        defer { harness.fixtures.removeAll() }
        let request = try harness.tone(seconds: 70)
        let before = try FileManager.default.contentsOfDirectory(atPath: harness.fixtures.directory.path).count
        let engine = harness.engine(FakeCloudSpeechTransport([CloudSpeechEngineTests.answered]))
        _ = try await engine.recognize(request) { _ in }
        #expect(try FileManager.default.contentsOfDirectory(atPath: harness.fixtures.directory.path).count == before)
    }
}
