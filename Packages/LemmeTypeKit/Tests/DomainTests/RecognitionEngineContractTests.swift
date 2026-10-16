import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

struct RecognitionEngineContractTests {
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-Recognition-\(UUID().uuidString)", isDirectory: true)

    /// The fake engine never reads the file, but the contract checks it is
    /// not deleted, so it must exist. It holds no audio, so it does not use an
    /// audio extension (which `make privacy-check` would flag).
    static func makeRequest(seconds: TimeInterval = 2, language: String = "en-US") throws -> RecognitionRequest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).placeholder")
        try Data().write(to: url)
        return RecognitionRequest(
            audio: RecordedAudio(fileURL: url, duration: seconds, format: .speech), language: language)
    }

    @Test(arguments: [
        EngineAvailability.ready, .assetsMissing, .unsupported(.hardware), .permissionUnavailable,
        .failed(.modelLoadFailed),
    ])
    func fakeEngineSatisfiesTheContract(availability: EngineAvailability) async throws {
        let engine = FakeRecognitionEngine(availability: availability)
        let issues = await RecognitionEngineContract.verify(engine, request: try Self.makeRequest())
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test func contractCatchesAnEngineThatIgnoresCancellation() async throws {
        let engine = FakeRecognitionEngine(script: .init(ignoresCancellation: true))
        let issues = await RecognitionEngineContract.verify(engine, request: try Self.makeRequest())
        #expect(issues.contains("engine returned a transcript after cancellation"))
    }

    @Test func availabilityDistinguishesEveryState() {
        let states: [EngineAvailability] = [
            .ready, .assetsMissing, .unsupported(.operatingSystem), .unsupported(.hardware),
            .permissionUnavailable, .failed(.engineFailure(code: 3)),
        ]
        #expect(Set(states.map(\.identifier)).count == states.count)
        #expect(states.filter(\.isReady) == [.ready])
        #expect(EngineAvailability.assetsMissing.recognitionError == .assetsMissing)
        #expect(EngineAvailability.permissionUnavailable.recognitionError == .permissionDenied)
        #expect(EngineAvailability.unsupported(.hardware).recognitionError == .unsupported(.hardware))
        #expect(states.allSatisfy { DiagnosticValue.isSafeIdentifier($0.identifier) })
    }

    @Test func errorIdentifiersAreStableAndSafe() {
        let errors: [RecognitionError] = [
            .cancelled, .assetsMissing, .unsupported(.language), .permissionDenied, .audioUnreadable,
            .noSpeechDetected, .modelLoadFailed, .engineFailure(code: 1),
        ]
        #expect(Set(errors.map(\.identifier)).count == errors.count)
        #expect(errors.allSatisfy { $0.identifier.hasPrefix("recognition.") })
        #expect(errors.allSatisfy { DiagnosticValue.isSafeIdentifier($0.identifier) })
    }

    @Test func transcriptCarriesTextSegmentsTimingEngineLanguageAndDuration() async throws {
        let engine = FakeRecognitionEngine(script: .init(text: "Ship it on Wednesday."))
        let transcript = try await RecognitionRunner().run(engine, try Self.makeRequest(seconds: 3.5))

        #expect(transcript.text == "Ship it on Wednesday.")
        #expect(transcript.segments.count == 1)
        #expect(transcript.segments.first?.confidence == 1)
        #expect(transcript.engine == engine.descriptor.id)
        #expect(transcript.language == "en-US")
        #expect(transcript.audioDuration == 3.5)
        #expect(transcript.processingDuration >= 0)
    }

    @Test func metricsCarryNoText() async throws {
        let engine = FakeRecognitionEngine(script: .init(text: "canary-secret-words"))
        let transcript = try await RecognitionRunner().run(engine, try Self.makeRequest())
        #expect(!String(describing: transcript.metrics).contains("canary"))
        #expect(transcript.metrics.isEmpty == false)
    }

    @Test func languageMatchingUsesTheLanguageCode() {
        let descriptor = EngineDescriptor(
            id: .whisper, supportedLanguages: ["en"], assets: .none, capabilities: [])
        #expect(descriptor.supports(language: "en-US"))
        #expect(descriptor.supports(language: "en"))
        #expect(!descriptor.supports(language: "fr-FR"))
    }
}

struct RecognitionRunnerTests {
    @Test func unavailableEngineIsNeverCalled() async throws {
        let engine = FakeRecognitionEngine(availability: .assetsMissing)
        await #expect(throws: RecognitionError.assetsMissing) {
            try await RecognitionRunner().run(engine, try RecognitionEngineContractTests.makeRequest())
        }
        #expect(engine.recognizeCount == 0)
    }

    @Test func unsupportedLanguageFailsBeforeRecognition() async throws {
        let engine = FakeRecognitionEngine()
        await #expect(throws: RecognitionError.unsupported(.language)) {
            try await RecognitionRunner().run(
                engine, try RecognitionEngineContractTests.makeRequest(language: "de-DE"))
        }
        #expect(engine.recognizeCount == 0)
    }

    @Test func cancellationDuringRecognitionThrowsCancelledPromptly() async throws {
        let engine = FakeRecognitionEngine(script: .init(delay: .seconds(30)))
        let request = try RecognitionEngineContractTests.makeRequest()
        let start = ContinuousClock.now
        let task = Task { try await RecognitionRunner().run(engine, request) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let result = await task.result
        #expect(throws: RecognitionError.cancelled) { try result.get() }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func cancelledSessionNeverReportsSuccessEvenIfTheEngineReturns() async throws {
        let engine = FakeRecognitionEngine(script: .init(delay: .milliseconds(200), ignoresCancellation: true))
        let request = try RecognitionEngineContractTests.makeRequest()
        let task = Task { try await RecognitionRunner().run(engine, request) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let result = await task.result
        #expect(throws: RecognitionError.cancelled) { try result.get() }
    }

    @Test func updatesStopAfterCancellation() async throws {
        let received = Mutex<[RecognitionUpdate]>([])
        let engine = FakeRecognitionEngine(
            script: .init(partials: ["Ship"], delay: .seconds(30)))
        let request = try RecognitionEngineContractTests.makeRequest()
        let task = Task {
            try await RecognitionRunner().run(engine, request) { update in
                received.withLock { $0.append(update) }
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = await task.result

        #expect(received.withLock { $0 } == [.partial("Ship")])
    }

    @Test func engineErrorsPassThroughUnchanged() async throws {
        let engine = FakeRecognitionEngine(script: .init(error: .noSpeechDetected))
        await #expect(throws: RecognitionError.noSpeechDetected) {
            try await RecognitionRunner().run(engine, try RecognitionEngineContractTests.makeRequest())
        }
    }

    @Test func retryableErrorsAreTheTransientOnes() {
        #expect(RecognitionError.engineFailure(code: 1).isRetryable)
        #expect(!RecognitionError.permissionDenied.isRetryable)
        #expect(!RecognitionError.cancelled.isRetryable)
    }
}
