import Domain
import Foundation
import Recognition
import TestSupport
import Testing

/// E12-S1: nothing is sent without consent and a key, and a failed upload keeps the recording.
struct CloudSpeechGateTests {
    static let answered = FakeCloudSpeechTransport.Step.respond(status: 200, body: Data(#"{"transcript":"x"}"#.utf8))
    let fixtures = RecordingFixtures()
    let sarvam = SarvamProvider()

    private func engine(
        _ transport: FakeCloudSpeechTransport, store: FakeCloudCredentialStore, consent: FakeCloudSpeechConsent
    ) -> CloudSpeechEngine {
        CloudSpeechEngine(
            provider: sarvam, transport: transport,
            credentials: ConsentedCloudCredentials(store: store, consent: consent))
    }

    private func storeWithKey() throws -> FakeCloudCredentialStore {
        let store = FakeCloudCredentialStore()
        try store.save(CloudCredential(secret: "k"), for: sarvam.id)
        return store
    }

    @Test func aKeyWithoutConsentSendsNothing() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([Self.answered])
        let engine = engine(transport, store: try storeWithKey(), consent: FakeCloudSpeechConsent())
        #expect(await engine.availability() == .permissionUnavailable)
        let request = try fixtures.make(.tone(seconds: 1), language: "te")
        await #expect(throws: RecognitionError.permissionDenied) {
            try await engine.recognize(request) { _ in }
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func consentWithoutAKeySendsNothing() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([Self.answered])
        let engine = engine(transport, store: FakeCloudCredentialStore(), consent: FakeCloudSpeechConsent(sarvam.id))
        #expect(await engine.availability() == .permissionUnavailable)
        #expect(transport.requests.isEmpty)
    }

    @Test func consentForAnotherProviderSendsNothing() async throws {
        let transport = FakeCloudSpeechTransport([Self.answered])
        let consent = FakeCloudSpeechConsent(CloudSpeechProviderID(rawValue: "someone-else"))
        let engine = engine(transport, store: try storeWithKey(), consent: consent)
        #expect(await engine.availability() == .permissionUnavailable)
    }

    @Test func consentAndAKeySend() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([Self.answered])
        let engine = engine(transport, store: try storeWithKey(), consent: FakeCloudSpeechConsent(sarvam.id))
        _ = try await engine.recognize(try fixtures.make(.tone(seconds: 1), language: "te")) { _ in }
        #expect(transport.requests.count == 1)
    }

    /// iOS can interrupt an upload when the app leaves the screen.
    @Test func anInterruptedUploadOnIPhoneKeepsTheRecordingAndSaysWhy() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([.fail(.offline)])
        let cloud = engine(transport, store: try storeWithKey(), consent: FakeCloudSpeechConsent(sarvam.id))
        let local = FakeRecognitionEngine(id: .whisper, supportedLanguages: ["te"])
        let recording = try fixtures.make(.tone(seconds: 1), language: "te")
        let mode = DictationMode(name: "Telugu", engine: .cloud, language: "te", writingMode: .exact)
        let session = DictationSession(
            audio: recording.audio,
            target: ActivationTarget(
                processIdentifier: 1, bundleIdentifier: nil, applicationName: "Test", focusedElement: nil),
            mode: .exact, dictationMode: mode, language: "te",
            enginePreference: EnginePreference(selected: .cloud, fallsBackAutomatically: true))
        let pipeline = TranscriptionPipeline(
            engines: [local, cloud], delivery: FakeTextDelivery(), reviewsEveryResult: true)

        let outcome = await pipeline.process(session) { _ in }

        guard case .needsAttention(let issue, let engine, _, _) = outcome else {
            Issue.record("expected needsAttention, got \(outcome)")
            return
        }
        #expect(issue == .recognitionFailed(.cloudOffline))
        #expect(engine == .cloud)
        #expect(local.recognizeCount == 0, "a failure never switches engine by itself")
        #expect(FileManager.default.fileExists(atPath: recording.audio.fileURL.path))
    }
}
