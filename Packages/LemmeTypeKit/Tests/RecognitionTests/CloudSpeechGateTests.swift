import Domain
import Foundation
import Recognition
import TestSupport
import Testing

/// E12-S1 and E13-S3: nothing is sent without an agreement to the current terms and a subscription, and a
/// failed upload keeps the recording.
struct CloudSpeechGateTests {
    static let answered = FakeCloudSpeechTransport.Step.respond(status: 200, body: Data(#"{"text":"x"}"#.utf8))
    let fixtures = RecordingFixtures()
    let gateway = GatewaySpeechProvider(host: "gateway.test")
    let access = FakeGatewayAccess()

    private func engine(_ transport: FakeCloudSpeechTransport, consent: FakeCloudSpeechConsent) -> CloudSpeechEngine {
        CloudSpeechEngine(
            provider: gateway, transport: GatewayTransport(base: transport, access: access),
            credentials: GatewayCredentials(consent: consent, access: access, directory: access))
    }

    @Test func noAgreementSendsNothing() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([Self.answered])
        let engine = engine(transport, consent: FakeCloudSpeechConsent())
        #expect(await engine.availability() == .permissionUnavailable)
        let request = try fixtures.make(.tone(seconds: 1), language: "te")
        await #expect(throws: RecognitionError.permissionDenied) {
            try await engine.recognize(request) { _ in }
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func anAgreementForAnotherProviderSendsNothing() async {
        let transport = FakeCloudSpeechTransport([Self.answered])
        let engine = engine(transport, consent: FakeCloudSpeechConsent(CloudSpeechProviderID(rawValue: "sarvam")))
        #expect(await engine.availability() == .permissionUnavailable)
        #expect(transport.requests.isEmpty)
    }

    @Test func aNewerVersionOfTheTermsAsksAgainBeforeAnyCloudUse() async throws {
        defer { fixtures.removeAll() }
        access.setConsentVersion(2)
        let transport = FakeCloudSpeechTransport([Self.answered])
        let engine = engine(transport, consent: FakeCloudSpeechConsent(gateway.id, version: 1))
        #expect(await engine.availability() == .permissionUnavailable)
        await #expect(throws: RecognitionError.permissionDenied) {
            try await engine.recognize(try fixtures.make(.tone(seconds: 1), language: "te")) { _ in }
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func noSubscriptionSendsNothing() async {
        access.setHasSubscription(false)
        let transport = FakeCloudSpeechTransport([Self.answered])
        let engine = engine(transport, consent: FakeCloudSpeechConsent(gateway.id))
        #expect(await engine.availability() == .permissionUnavailable)
        #expect(transport.requests.isEmpty)
    }

    @Test func anAgreementStandsWhenTheGatewayCannotBeReachedToCheckIt() async {
        access.setCapabilitiesFailure(.offline)
        let engine = engine(FakeCloudSpeechTransport([Self.answered]), consent: FakeCloudSpeechConsent(gateway.id))
        #expect(await engine.availability() == .ready, "the upload itself will report that it is offline")
    }

    @Test func anAgreementAndASubscriptionSendWithTheAccessToken() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([Self.answered])
        let engine = engine(transport, consent: FakeCloudSpeechConsent(gateway.id))
        let transcript = try await engine.recognize(try fixtures.make(.tone(seconds: 1), language: "te")) { _ in }
        #expect(transcript.text == "x")
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.url.host() == "gateway.test")
        #expect(transport.requests.first?.headers["Authorization"] == "Bearer test-token-1")
    }

    /// iOS can interrupt an upload when the app leaves the screen.
    @Test func anInterruptedUploadOnIPhoneKeepsTheRecordingAndSaysWhy() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([.fail(.offline)])
        let cloud = engine(transport, consent: FakeCloudSpeechConsent(gateway.id))
        let local = FakeRecognitionEngine(id: .whisper, supportedLanguages: ["te"])
        let recording = try fixtures.make(.tone(seconds: 1), language: "te")
        let pipeline = TranscriptionPipeline(
            engines: [local, cloud], delivery: FakeTextDelivery(), reviewsEveryResult: true)

        let outcome = await pipeline.process(session(for: recording)) { _ in }

        guard case .needsAttention(let issue, let engine, _, _) = outcome else {
            Issue.record("expected needsAttention, got \(outcome)")
            return
        }
        #expect(issue == .recognitionFailed(.cloudOffline))
        #expect(engine == .cloud)
        #expect(local.recognizeCount == 0, "a failure never switches engine by itself")
        #expect(FileManager.default.fileExists(atPath: recording.audio.fileURL.path))
    }

    /// Telugu speech with English output ends in the existing review, and nothing is delivered yet.
    @Test func teluguToEnglishEndsInTheTranslationReviewAndDeliversNothing() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([
            .respond(status: 200, body: Data(#"{"text":"Ship it on Wednesday."}"#.utf8))
        ])
        let delivery = FakeTextDelivery()
        let recording = try fixtures.make(.tone(seconds: 1), language: "te")
        let pipeline = TranscriptionPipeline(
            engines: [engine(transport, consent: FakeCloudSpeechConsent(gateway.id))], delivery: delivery)

        let outcome = await pipeline.process(session(for: recording, output: .english)) { _ in }

        guard case .needsAttention(.reviewTranslation, _, _, let text?) = outcome else {
            Issue.record("expected the translation review, got \(outcome)")
            return
        }
        #expect(text == "Ship it on Wednesday.")
        #expect(delivery.delivered.isEmpty, "nothing is delivered before the user chooses")
        // The body holds binary audio, so it is read as Latin-1, which never fails.
        let sent = String(bytes: transport.requests.first?.body ?? Data(), encoding: .isoLatin1) ?? ""
        #expect(sent.contains("name=\"task\"\r\n\r\ntranslate"))
        #expect(sent.contains("name=\"language\"\r\n\r\nte"))
    }

    private func session(for recording: RecognitionRequest, output: SpeechOutput = .original)
        -> DictationSession
    {
        let mode = DictationMode(name: "Telugu", engine: .cloud, language: "te", writingMode: .exact)
        return DictationSession(
            audio: recording.audio,
            target: ActivationTarget(
                processIdentifier: 1, bundleIdentifier: nil, applicationName: "Test", focusedElement: nil),
            mode: .exact, dictationMode: mode, language: "te", speechOutput: output,
            enginePreference: EnginePreference(selected: .cloud, fallsBackAutomatically: true))
    }
}
