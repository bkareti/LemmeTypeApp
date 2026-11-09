import Domain
import Foundation
import Recognition
import TestSupport
import Testing

/// A second vendor that exists only here. It proves a provider can be replaced
/// by adding one type, with nothing else in the app changing.
struct ExampleCloudProvider: CloudSpeechProvider {
    let id = CloudSpeechProviderID(rawValue: "example")
    let displayName = "Example"
    let host = "speech.example.com"
    let maximumClipSeconds = 60.0
    let supportedLanguages = ["te"]
    let tasks: Set<RecognitionTask> = [.transcribe]

    func request(
        for clip: CloudAudioClip, need: RecognitionNeed, credential: CloudCredential
    ) throws(RecognitionError) -> CloudHTTPRequest {
        guard supportedLanguages.contains(need.language), let url = URL(string: "https://\(host)/v1/listen") else {
            throw .unsupported(.language)
        }
        return CloudHTTPRequest(url: url, headers: ["Authorization": "Bearer \(credential.secret)"], body: clip.wav)
    }

    func transcript(from response: CloudHTTPResponse) throws(RecognitionError) -> String {
        switch response.status {
        case 200:
            let text = String(bytes: response.body, encoding: .utf8) ?? ""
            guard text.hasPrefix("text:") else { throw .cloudServiceFailed }
            return String(text.dropFirst(5))
        case 401, 403: throw .cloudKeyRejected
        case 429: throw .cloudRateLimited
        default: throw .cloudServiceFailed
        }
    }
}

struct CloudSpeechEngineTests {
    static let answer = Data(#"{"transcript":"  రేపు   team meeting  "}"#.utf8)
    static let answered = FakeCloudSpeechTransport.Step.respond(status: 200, body: answer)
    static let limited = FakeCloudSpeechTransport.Step.respond(status: 429, body: Data("{}".utf8))
    static let broken = FakeCloudSpeechTransport.Step.respond(status: 500, body: Data("{}".utf8))

    let fixtures = RecordingFixtures()

    func engine(
        _ transport: FakeCloudSpeechTransport, secret: String? = "test-key",
        clock: any Clock<Duration> = ContinuousClock(),
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) -> CloudSpeechEngine {
        CloudSpeechEngine(
            provider: SarvamProvider(), transport: transport, credentials: FakeCloudCredentials(secret: secret),
            clock: clock, diagnostics: diagnostics)
    }

    func tone(seconds: Double = 1, language: String = "te") throws -> RecognitionRequest {
        try fixtures.make(.tone(seconds: seconds), language: language)
    }

    static func outcome(
        _ engine: CloudSpeechEngine, _ request: RecognitionRequest
    ) async -> Result<Transcript, RecognitionError> {
        do throws(RecognitionError) {
            return .success(try await engine.recognize(request) { _ in })
        } catch {
            return .failure(error)
        }
    }

    /// Runs `engine`, letting every backoff on `clock` finish.
    func runAdvancing(
        _ engine: CloudSpeechEngine, _ request: RecognitionRequest, clock: ManualClock
    ) async -> Result<Transcript, RecognitionError> {
        let task = Task { await Self.outcome(engine, request) }
        let driver = Task {
            while !Task.isCancelled {
                if clock.sleeperCount > 0 { clock.advance(by: .seconds(10)) }
                await Task.yield()
            }
        }
        let result = await task.value
        driver.cancel()
        return result
    }

    func failure(_ result: Result<Transcript, RecognitionError>) -> RecognitionError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    // MARK: Contracts

    @Test func passesTheEngineContract() async throws {
        defer { fixtures.removeAll() }
        let engine = engine(FakeCloudSpeechTransport([Self.answered]))
        #expect(engine.descriptor.id == .cloud)
        #expect(engine.descriptor.location == .cloud)
        let issues = await RecognitionEngineContract.verify(engine, request: try tone(), location: .cloud)
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test func aSecondProviderWorksWithNoOtherChange() async throws {
        defer { fixtures.removeAll() }
        let provider = ExampleCloudProvider()
        let fixture = CloudSpeechProviderContract.Fixture(
            need: RecognitionNeed(language: "te"), successBody: Data("text:నమస్తే".utf8), expectedText: "నమస్తే")
        #expect(CloudSpeechProviderContract.verify(provider, fixture: fixture).isEmpty)

        let transport = FakeCloudSpeechTransport([.respond(status: 200, body: fixture.successBody)])
        let engine = CloudSpeechEngine(provider: provider, transport: transport, credentials: FakeCloudCredentials())
        let issues = await RecognitionEngineContract.verify(engine, request: try tone(), location: .cloud)
        #expect(issues.isEmpty, "\(issues)")
        #expect(transport.requests.first?.url.host() == "speech.example.com")
        #expect(engine.descriptor.id == .cloud, "the rest of the app never sees the vendor")
    }

    // MARK: Results

    @Test func returnsTidyTextForTheSpokenLanguage() async throws {
        defer { fixtures.removeAll() }
        let transcript = try await engine(FakeCloudSpeechTransport([Self.answered])).recognize(try tone()) { _ in }
        #expect(transcript.text == "రేపు team meeting")
        #expect(transcript.engine == .cloud)
        #expect(transcript.language == "te")
        #expect(transcript.spokenLanguage == "te")
    }

    @Test func aTranslationIsMarkedAsEnglish() async throws {
        defer { fixtures.removeAll() }
        let spoken = try tone()
        let request = RecognitionRequest(audio: spoken.audio, language: "te", task: .translateToEnglish)
        let transcript = try await engine(FakeCloudSpeechTransport([Self.answered])).recognize(request) { _ in }
        #expect(transcript.language == "en")
        #expect(transcript.spokenLanguage == "te")
    }

    @Test func anEmptyAnswerMeansNoSpeech() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([.respond(status: 200, body: Data(#"{"transcript":"  "}"#.utf8))])
        let request = try tone()
        await #expect(throws: RecognitionError.noSpeechDetected) {
            try await engine(transport).recognize(request) { _ in }
        }
    }

    @Test func sendsSixteenBitWAV() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([Self.answered])
        _ = try await engine(transport).recognize(try tone()) { _ in }
        let body = try #require(transport.requests.first?.body)
        #expect(body.range(of: Data("RIFF".utf8)) != nil)
        #expect(body.range(of: Data("WAVEfmt ".utf8)) != nil)
    }

    // MARK: Nothing is sent

    @Test func withoutAKeyItCannotRunAndSendsNothing() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([Self.answered])
        let engine = engine(transport, secret: nil)
        #expect(await engine.availability() == .permissionUnavailable)
        let request = try tone()
        await #expect(throws: RecognitionError.permissionDenied) {
            try await engine.recognize(request) { _ in }
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func silenceIsNeverUploaded() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([Self.answered])
        let request = try fixtures.make(.silence(seconds: 1), language: "te")
        await #expect(throws: RecognitionError.silentAudio) {
            try await engine(transport).recognize(request) { _ in }
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func anUnsupportedLanguageSendsNothing() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([Self.answered])
        let request = try tone(language: "en-US")
        await #expect(throws: RecognitionError.unsupported(.language)) {
            try await engine(transport).recognize(request) { _ in }
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func vocabularyHintsNeverLeaveTheMac() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([Self.answered])
        let spoken = try tone()
        let request = RecognitionRequest(audio: spoken.audio, language: "te", hints: ["canary-hint-9c1"])
        _ = try await engine(transport).recognize(request) { _ in }
        let sent = try #require(transport.requests.first)
        #expect(sent.body.range(of: Data("canary-hint-9c1".utf8)) == nil)
        #expect(!sent.url.absoluteString.contains("canary-hint-9c1"))
    }

    // MARK: Retries

    @Test(arguments: [Self.limited, Self.broken])
    func aPassingProblemIsRetried(first: FakeCloudSpeechTransport.Step) async throws {
        defer { fixtures.removeAll() }
        let clock = ManualClock()
        let transport = FakeCloudSpeechTransport([first, first, Self.answered])
        let result = await runAdvancing(engine(transport, clock: clock), try tone(), clock: clock)
        #expect((try? result.get())?.text == "రేపు team meeting")
        #expect(transport.requests.count == 3)
    }

    @Test func retriesStopAfterTwo() async throws {
        defer { fixtures.removeAll() }
        for (step, expected) in [
            (Self.limited, RecognitionError.cloudRateLimited), (Self.broken, RecognitionError.cloudServiceFailed),
        ] {
            let clock = ManualClock()
            let transport = FakeCloudSpeechTransport([step])
            let result = await runAdvancing(engine(transport, clock: clock), try tone(), clock: clock)
            #expect(failure(result) == expected)
            #expect(transport.requests.count == 1 + CloudSpeechEngine.maximumRetries)
        }
    }

    @Test func problemsThatCannotClearUpAreNotRetried() async throws {
        defer { fixtures.removeAll() }
        let quota = Data(#"{"error":{"code":"insufficient_quota_error"}}"#.utf8)
        let cases: [(FakeCloudSpeechTransport.Step, RecognitionError)] = [
            (.respond(status: 403, body: Data("{}".utf8)), .cloudKeyRejected),
            (.respond(status: 429, body: quota), .cloudQuotaExhausted),
            (.respond(status: 400, body: Data("{}".utf8)), .cloudServiceFailed),
            (.fail(.offline), .cloudOffline),
            (.fail(.timedOut), .cloudServiceFailed),
            (.fail(.hostRefused), .cloudServiceFailed),
        ]
        for (step, expected) in cases {
            let transport = FakeCloudSpeechTransport([step])
            let request = try tone()
            await #expect(throws: expected) {
                try await engine(transport).recognize(request) { _ in }
            }
            #expect(transport.requests.count == 1)
        }
    }

    // MARK: Cancellation

    @Test func cancellingStopsTheRequestAndReturnsNoText() async throws {
        defer { fixtures.removeAll() }
        let transport = FakeCloudSpeechTransport([.hang])
        let engine = engine(transport)
        let request = try tone()
        let task = Task { await Self.outcome(engine, request) }
        while transport.requests.isEmpty { await Task.yield() }
        task.cancel()
        #expect(failure(await task.value) == .cancelled)
    }

    @Test func cancellingDuringABackoffStopsRetrying() async throws {
        defer { fixtures.removeAll() }
        let clock = ManualClock()
        let transport = FakeCloudSpeechTransport([Self.limited])
        let engine = engine(transport, clock: clock)
        let request = try tone()
        let task = Task { await Self.outcome(engine, request) }
        while clock.sleeperCount == 0 { await Task.yield() }
        task.cancel()
        #expect(failure(await task.value) == .cancelled)
        #expect(transport.requests.count == 1)
    }

    // MARK: Privacy

    @Test func noTranscriptAudioOrKeyReachesDiagnosticsOrErrors() async throws {
        defer { fixtures.removeAll() }
        let canaryText = "canary-transcript-41d"
        let canaryKey = "canary-key-41d"
        let answer = Data(#"{"transcript":"\#(canaryText)"}"#.utf8)
        let refused = Data(#"{"error":{"code":"invalid_api_key_error","message":"\#(canaryKey)"}}"#.utf8)

        let diagnostics = RecordingDiagnostics()
        let succeeding = engine(
            FakeCloudSpeechTransport([.respond(status: 200, body: answer)]), secret: canaryKey, diagnostics: diagnostics
        )
        _ = try await succeeding.recognize(try tone()) { _ in }

        let transport = FakeCloudSpeechTransport([.respond(status: 403, body: refused)])
        let failing = engine(transport, secret: canaryKey, diagnostics: diagnostics)
        var thrown = ""
        if case .failure(let error) = await Self.outcome(failing, try tone()) {
            thrown = "\(error) \(String(reflecting: error)) \(error.identifier)"
        }
        #expect(thrown.contains("cloudKeyRejected"))

        let events = try JSONEncoder().encode(diagnostics.events)
        let written = (String(bytes: events, encoding: .utf8) ?? "") + thrown
        #expect(!written.contains(canaryText))
        #expect(!written.contains(canaryKey))
        #expect(!written.contains("RIFF"))
        #expect(diagnostics.events.contains { $0.name == "cloud-failed" })

        let sent = try #require(transport.requests.first)
        #expect(!"\(sent) \(String(reflecting: sent))".contains(canaryKey), "a request prints only its host")
        #expect(!"\(CloudCredential(secret: canaryKey))".contains(canaryKey))
    }
}
