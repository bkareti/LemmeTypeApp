import Domain
import Foundation
import TestSupport
import Testing

/// A cloud engine runs only when the user picked it (ADR 0031).
struct CloudEngineSelectionTests {
    @Test func theCloudEngineIsUsedWhenItIsPreferred() {
        #expect(
            EngineSelector.choose(preferred: .cloud, candidates: [(.whisper, .ready), (.cloud, .ready)])
                == .engine(.cloud))
    }

    @Test func automaticNeverPicksTheCloudEngine() {
        #expect(
            EngineSelector.choose(preferred: nil, candidates: [(.cloud, .ready), (.whisper, .ready)])
                == .engine(.whisper))
        #expect(EngineSelector.choose(preferred: nil, candidates: [(.cloud, .ready)]) == .noneAvailable)
    }

    @Test func fallbackNeverMovesALocalChoiceToTheCloud() {
        let choice = EngineSelector.choose(
            preferred: .whisper, fallsBackAutomatically: true,
            candidates: [(.whisper, .assetsMissing), (.cloud, .ready)])
        #expect(choice == .unavailable(.whisper, .assetsMissing, alternatives: []))
    }

    @Test func aMissingPreferredEngineNeverBecomesTheCloudEngine() {
        let removed = RecognitionEngineID(rawValue: "removed")
        #expect(EngineSelector.choose(preferred: removed, candidates: [(.cloud, .ready)]) == .noneAvailable)
    }

    @Test func theCloudEngineIsNeverOfferedAsAnAlternative() {
        let choice = EngineSelector.choose(
            preferred: .appleSpeech, candidates: [(.appleSpeech, .assetsMissing), (.cloud, .ready), (.whisper, .ready)])
        #expect(choice == .unavailable(.appleSpeech, .assetsMissing, alternatives: [.whisper]))
    }

    @Test func aCloudChoiceThatCannotRunStaysThatChoice() {
        let choice = EngineSelector.choose(
            preferred: .cloud, fallsBackAutomatically: false,
            candidates: [(.cloud, .permissionUnavailable), (.whisper, .ready)])
        #expect(choice == .unavailable(.cloud, .permissionUnavailable, alternatives: [.whisper]))
    }

    @Test func aFailedLocalEngineDoesNotOfferTheCloudEngine() async throws {
        let whisper = FakeRecognitionEngine(id: .whisper, script: .init(error: .engineFailure(code: 7)))
        let cloud = FakeRecognitionEngine(id: .cloud)
        let apple = FakeRecognitionEngine(id: .appleSpeech)
        let session = try TranscriptionPipelineTests.makeSession(engine: .whisper)
        let outcome = await TranscriptionPipeline(
            engines: [whisper, cloud, apple], delivery: FakeTextDelivery()
        ).process(session) { _ in }
        guard case .needsAttention(_, _, let alternatives, _) = outcome else {
            Issue.record("expected needsAttention, got \(outcome)")
            return
        }
        #expect(alternatives == [.appleSpeech])
    }

    @Test func cloudFailuresHaveStableIdentifiersAndTheRightRetries() {
        let identifiers: [(RecognitionError, String)] = [
            (.cloudOffline, "recognition.cloud-offline"),
            (.cloudKeyRejected, "recognition.cloud-key-rejected"),
            (.cloudRateLimited, "recognition.cloud-rate-limited"),
            (.cloudQuotaExhausted, "recognition.cloud-quota-exhausted"),
            (.cloudServiceFailed, "recognition.cloud-service-failed"),
        ]
        for (error, identifier) in identifiers {
            #expect(error.identifier == identifier)
        }
        #expect(RecognitionError.cloudOffline.isRetryable)
        #expect(RecognitionError.cloudRateLimited.isRetryable)
        #expect(RecognitionError.cloudServiceFailed.isRetryable)
        #expect(!RecognitionError.cloudKeyRejected.isRetryable)
        #expect(!RecognitionError.cloudQuotaExhausted.isRetryable)
    }

    @Test func aMissingKeyDoesNotAskForSpeechRecognitionAccess() {
        let actions = DictationIssue.engineUnavailable(.cloud, .permissionUnavailable)
            .actions(alternatives: [.whisper])
        #expect(actions == [.useEngine(.whisper), .chooseEngine, .saveAudio, .discard])
        #expect(!actions.contains(.allowSpeechRecognition))
    }

    @Test func aPassingCloudFailureOffersRetryAndAnotherEngine() {
        #expect(
            DictationIssue.recognitionFailed(.cloudOffline).actions(alternatives: [.whisper])
                == [.retry, .useEngine(.whisper), .saveAudio, .discard])
    }
}
