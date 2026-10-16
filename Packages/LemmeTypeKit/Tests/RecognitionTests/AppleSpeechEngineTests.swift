import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Recognition

/// Scriptable stand-in for the Speech framework.
final class FakeAppleSpeechBackend: AppleSpeechBackend {
    struct Config {
        var hasRecognizer = true
        var supportsOnDevice = true
        var result = AppleSpeechResult(
            text: "Meet me at noon.",
            segments: [TranscriptSegment(text: "Meet", start: 0, duration: 0.3, confidence: 0.9)])
        var partials: [String] = ["Meet", "Meet me"]
        var error: RecognitionError?
        var delay: Duration = .zero
    }

    private let config: Mutex<Config>
    private let calls = Mutex(0)

    init(_ config: Config = Config()) {
        self.config = Mutex(config)
    }

    var recognizeCount: Int { calls.withLock { $0 } }

    func hasRecognizer(language: String) -> Bool { config.withLock { $0.hasRecognizer } }
    func supportsOnDeviceRecognition(language: String) -> Bool { config.withLock { $0.supportsOnDevice } }

    func recognize(
        fileURL: URL,
        language: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws(RecognitionError) -> AppleSpeechResult {
        calls.withLock { $0 += 1 }
        let config = config.withLock { $0 }
        config.partials.forEach(onPartial)
        if config.delay > .zero {
            do { try await Task.sleep(for: config.delay) } catch { throw .cancelled }
        }
        if let error = config.error { throw error }
        return config.result
    }
}

struct AppleSpeechEngineTests {
    private let fixtures = RecordingFixtures()

    private func makeEngine(
        _ config: FakeAppleSpeechBackend.Config = .init(),
        authorization: PermissionStatus = .granted,
        language: String = "en-US"
    ) -> (AppleSpeechEngine, FakeAppleSpeechBackend) {
        let backend = FakeAppleSpeechBackend(config)
        let engine = AppleSpeechEngine(
            backend: backend, authorizer: FakeSpeechAuthorizer(status: authorization), language: { language })
        return (engine, backend)
    }

    @Test func normalSpeechProducesOneFinalTranscriptWithPartials() async throws {
        defer { fixtures.removeAll() }
        let (engine, _) = makeEngine()
        let partials = Mutex<[RecognitionUpdate]>([])

        let transcript = try await RecognitionRunner().run(engine, try fixtures.make(.tone(seconds: 1))) { update in
            partials.withLock { $0.append(update) }
        }

        #expect(transcript.text == "Meet me at noon.")
        #expect(transcript.engine == .appleSpeech)
        #expect(transcript.language == "en-US")
        #expect(abs(transcript.audioDuration - 1) < 0.01)
        #expect(transcript.segments.first?.confidence == 0.9)
        #expect(partials.withLock { $0 } == [.partial("Meet"), .partial("Meet me")])
    }

    @Test func emptyAudioIsNoSpeechWithoutCallingTheFramework() async throws {
        defer { fixtures.removeAll() }
        let (engine, backend) = makeEngine()
        await #expect(throws: RecognitionError.noSpeechDetected) {
            try await engine.recognize(try fixtures.make(.empty)) { _ in }
        }
        #expect(backend.recognizeCount == 0)
    }

    @Test func silenceIsNoSpeechWithoutCallingTheFramework() async throws {
        defer { fixtures.removeAll() }
        let (engine, backend) = makeEngine()
        await #expect(throws: RecognitionError.noSpeechDetected) {
            try await engine.recognize(try fixtures.make(.silence(seconds: 1))) { _ in }
        }
        #expect(backend.recognizeCount == 0)
    }

    @Test func blankFrameworkResultIsNoSpeech() async throws {
        defer { fixtures.removeAll() }
        var config = FakeAppleSpeechBackend.Config()
        config.result = AppleSpeechResult(text: "  ", segments: [])
        let (engine, _) = makeEngine(config)
        await #expect(throws: RecognitionError.noSpeechDetected) {
            try await engine.recognize(try fixtures.make(.tone(seconds: 1))) { _ in }
        }
    }

    @Test func missingOnDeviceSupportIsUnavailableAndNeverRecognises() async throws {
        defer { fixtures.removeAll() }
        var config = FakeAppleSpeechBackend.Config()
        config.supportsOnDevice = false
        let (engine, backend) = makeEngine(config)

        #expect(await engine.availability() == .unsupported(.onDeviceRecognitionUnavailable))
        await #expect(throws: RecognitionError.unsupported(.onDeviceRecognitionUnavailable)) {
            try await engine.recognize(try fixtures.make(.tone(seconds: 1))) { _ in }
        }
        #expect(backend.recognizeCount == 0)
    }

    @Test(arguments: [PermissionStatus.notRequested, .denied, .restricted])
    func missingAuthorizationIsReportedSeparatelyFromMicrophone(status: PermissionStatus) async throws {
        defer { fixtures.removeAll() }
        let (engine, backend) = makeEngine(authorization: status)
        let request = try fixtures.make(.tone(seconds: 1))

        #expect(await engine.availability() == .permissionUnavailable)
        await #expect(throws: RecognitionError.permissionDenied) {
            try await engine.recognize(request) { _ in }
        }
        #expect(backend.recognizeCount == 0)
        // The session still owns the recording for retry or cancel.
        #expect(FileManager.default.fileExists(atPath: request.audio.fileURL.path))
    }

    @Test func unknownLanguageIsUnsupported() async {
        var config = FakeAppleSpeechBackend.Config()
        config.hasRecognizer = false
        let (engine, _) = makeEngine(config)
        #expect(await engine.availability() == .unsupported(.language))
        let (french, _) = makeEngine(language: "fr-FR")
        #expect(await french.availability() == .unsupported(.language))
    }

    @Test func cancellationStopsRecognitionPromptly() async throws {
        defer { fixtures.removeAll() }
        var config = FakeAppleSpeechBackend.Config()
        config.delay = .seconds(30)
        let (engine, _) = makeEngine(config)
        let request = try fixtures.make(.tone(seconds: 1))
        let start = ContinuousClock.now

        let task = Task { try await RecognitionRunner().run(engine, request) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        #expect(throws: RecognitionError.cancelled) { try await task.value }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func frameworkErrorsPassThroughTheEngine() async throws {
        defer { fixtures.removeAll() }
        var config = FakeAppleSpeechBackend.Config()
        config.error = .engineFailure(code: 1101)
        let (engine, _) = makeEngine(config)
        await #expect(throws: RecognitionError.engineFailure(code: 1101)) {
            try await engine.recognize(try fixtures.make(.tone(seconds: 1))) { _ in }
        }
    }

    @Test(arguments: [
        ("kAFAssistantErrorDomain", 1110, RecognitionError.noSpeechDetected),
        ("kAFAssistantErrorDomain", 203, .noSpeechDetected),
        ("kAFAssistantErrorDomain", 216, .cancelled),
        ("kAFAssistantErrorDomain", 301, .cancelled),
        ("kAFAssistantErrorDomain", 1700, .unsupported(.onDeviceRecognitionUnavailable)),
        ("SFSpeechErrorDomain", 2, .audioUnreadable),
        ("NSCocoaErrorDomain", 42, .engineFailure(code: 42)),
    ])
    func frameworkErrorMapping(domain: String, code: Int, expected: RecognitionError) {
        #expect(AppleSpeechErrorMapping.map(domain: domain, code: code) == expected)
    }

    @Test func unreadableFileIsReported() async throws {
        defer { fixtures.removeAll() }
        let (engine, _) = makeEngine()
        let bogus = fixtures.directory.appendingPathComponent("missing.caf")
        let request = RecognitionRequest(
            audio: RecordedAudio(fileURL: bogus, duration: 1, format: .speech), language: "en-US")
        await #expect(throws: RecognitionError.audioUnreadable) {
            try await engine.recognize(request) { _ in }
        }
    }

    @Test(arguments: [EngineAvailability.ready, .permissionUnavailable, .unsupported(.onDeviceRecognitionUnavailable)])
    func satisfiesTheEngineContract(availability: EngineAvailability) async throws {
        defer { fixtures.removeAll() }
        var config = FakeAppleSpeechBackend.Config()
        config.supportsOnDevice = availability != .unsupported(.onDeviceRecognitionUnavailable)
        let (engine, _) = makeEngine(config, authorization: availability == .permissionUnavailable ? .denied : .granted)
        #expect(await engine.availability() == availability)

        let issues = await RecognitionEngineContract.verify(engine, request: try fixtures.make(.tone(seconds: 1)))
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test func authorizationStatusMapping() {
        #expect(SystemSpeechAuthorizer.status(from: .notDetermined) == .notRequested)
        #expect(SystemSpeechAuthorizer.status(from: .authorized) == .granted)
        #expect(SystemSpeechAuthorizer.status(from: .denied) == .denied)
        #expect(SystemSpeechAuthorizer.status(from: .restricted) == .restricted)
    }
}
