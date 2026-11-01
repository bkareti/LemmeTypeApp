import Domain
import Foundation
import TestSupport
import Testing

/// E6-S3: the pipeline offers the history exactly what the user received.
struct DictationHistoryPipelineTests {
    @Test func deliveredTextIsOfferedOnceAsInserted() async throws {
        let history = FakeDictationHistoryRecorder()
        let pipeline = TranscriptionPipeline(
            engines: [FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "ship it"))],
            delivery: FakeTextDelivery(), history: history)

        let outcome = await pipeline.process(try TranscriptionPipelineTests.makeSession()) { _ in }

        #expect(outcome == .delivered(.accessibility))
        #expect(history.calls.map(\.text) == ["ship it"])
        #expect(history.calls.map(\.delivery) == [.inserted])
    }

    @Test func aCopiedResultIsOfferedAsCopied() async throws {
        let history = FakeDictationHistoryRecorder()
        let delivery = FakeTextDelivery(outcome: .delivered(.copied))
        let pipeline = TranscriptionPipeline(
            engines: [FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "copy me"))],
            delivery: delivery, history: history)

        _ = await pipeline.process(try TranscriptionPipelineTests.makeSession()) { _ in }

        #expect(history.calls.map(\.delivery) == [.copied])
    }

    @Test func aFailedDeliveryOffersNothing() async throws {
        let history = FakeDictationHistoryRecorder()
        let pipeline = TranscriptionPipeline(
            engines: [FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "lost"))],
            delivery: FakeTextDelivery(outcome: .problem(.targetChanged)), history: history)

        let outcome = await pipeline.process(try TranscriptionPipelineTests.makeSession()) { _ in }

        guard case .needsAttention(.deliveryFailed, _, _, _) = outcome else {
            Issue.record("expected a delivery problem")
            return
        }
        #expect(history.calls.isEmpty)
    }

    @Test func aRecognitionFailureOffersNothing() async throws {
        let history = FakeDictationHistoryRecorder()
        let pipeline = TranscriptionPipeline(
            engines: [FakeRecognitionEngine(id: .appleSpeech, script: .init(error: .noSpeechDetected))],
            delivery: FakeTextDelivery(), history: history)

        _ = await pipeline.process(try TranscriptionPipelineTests.makeSession()) { _ in }

        #expect(history.calls.isEmpty)
    }

    @Test func retryDeliveryOffersTheTextOnceItIsDelivered() async throws {
        let history = FakeDictationHistoryRecorder()
        let pipeline = TranscriptionPipeline(
            engines: [FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "x"))],
            delivery: FakeTextDelivery(), history: history)

        _ = await pipeline.deliver("Retried text.", for: try TranscriptionPipelineTests.makeSession())

        #expect(history.calls.map(\.text) == ["Retried text."])
    }
}
