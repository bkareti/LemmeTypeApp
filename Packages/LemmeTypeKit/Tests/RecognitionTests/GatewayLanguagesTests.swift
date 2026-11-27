import Domain
import Foundation
import Recognition
import TestSupport
import Testing

/// E12-S7: the gateway decides which Cloud speech languages are live, and the app follows.
struct GatewayLanguagesTests {
    static let clip = CloudAudioClip(wav: Data("wav-bytes".utf8), seconds: 2)
    static let credential = CloudCredential(secret: "placeholder")

    private func need(_ language: String, _ task: RecognitionTask = .transcribe) -> RecognitionNeed {
        RecognitionNeed(language: language, task: task)
    }

    private func body(of request: CloudHTTPRequest) -> String {
        String(bytes: request.body, encoding: .utf8) ?? ""
    }

    // MARK: The list

    @Test func beforeTheGatewayHasAnsweredOnlyTeluguIsOffered() {
        let store = FakeCloudLanguageStore()
        let languages = GatewayLanguages(store: store)
        #expect(languages.languages == ["te"])
        #expect(store.cloudLanguages == nil, "nothing is written until the gateway answers")
    }

    @Test func theLastAnswerSurvivesARelaunch() {
        let store = FakeCloudLanguageStore()
        GatewayLanguages(store: store).update(["te", "hi"])
        #expect(store.cloudLanguages == ["te", "hi"])
        #expect(GatewayLanguages(store: store).languages == ["te", "hi"], "a new launch reads the stored list")
    }

    @Test func languagesTheAppCannotNameAreLeftOutAndCodesAreNormalised() {
        let languages = GatewayLanguages(store: FakeCloudLanguageStore())
        languages.update(["te-IN", "HI", "bn", "en", "te"])
        #expect(languages.languages == ["te", "hi"], "Bengali has no name in the app yet; English stays local")
    }

    @Test func updateReportsWhetherTheListChanged() {
        let languages = GatewayLanguages(store: FakeCloudLanguageStore())
        #expect(languages.update(["te"]) == false)
        #expect(languages.update(["te", "ta"]) == true)
        #expect(languages.update(["te", "ta"]) == false)
        #expect(languages.update(["te"]) == true, "a language the gateway stops serving is removed")
    }

    // MARK: The provider and engine follow the list

    @Test func theEngineOffersWhatTheGatewayLastListed() {
        let languages = GatewayLanguages(store: FakeCloudLanguageStore())
        let engine = CloudSpeechEngine(
            provider: GatewaySpeechProvider(host: "gateway.test", languages: languages),
            transport: FakeCloudSpeechTransport([]), credentials: FakeCloudCredentials())
        #expect(engine.descriptor.supportedLanguages == ["te"])
        languages.update(["te", "hi", "ta", "kn", "ml"])
        #expect(engine.descriptor.supportedLanguages == ["te", "hi", "ta", "kn", "ml"])
    }

    @Test(arguments: [("hi", RecognitionTask.transcribe, "transcribe"), ("ta", .translateToEnglish, "translate")])
    func aListedLanguageIsSentWithItsTask(language: String, task: RecognitionTask, field: String) throws {
        let languages = GatewayLanguages(store: FakeCloudLanguageStore(["te", "hi", "ta"]))
        let provider = GatewaySpeechProvider(host: "gateway.test", languages: languages, makeBoundary: { "B" })
        let request = try provider.request(for: Self.clip, need: need(language, task), credential: Self.credential)
        let body = body(of: request)
        #expect(body.contains("name=\"language\"\r\n\r\n\(language)\r\n"))
        #expect(body.contains("name=\"task\"\r\n\r\n\(field)\r\n"))
    }

    @Test func aLanguageTheGatewayDidNotListIsRefusedBeforeAnythingIsSent() {
        let provider = GatewaySpeechProvider(
            host: "gateway.test", languages: GatewayLanguages(store: FakeCloudLanguageStore(["te"])))
        #expect(throws: RecognitionError.unsupported(.language)) {
            try provider.request(for: Self.clip, need: need("ml"), credential: Self.credential)
        }
    }

    // MARK: The gateway's answer

    @Test func readingTheCapabilitiesUpdatesTheList() async throws {
        let answer = Data(
            #"""
            {"app":"lemmetype","consentVersion":1,"maximumClipSeconds":30,"tasks":["transcribe","translate"],
             "languages":[{"language":"te","tasks":["transcribe","translate"]},
                          {"language":"hi","tasks":["transcribe","translate"]},
                          {"language":"kn","tasks":["translate"]}]}
            """#.utf8)
        let languages = GatewayLanguages(store: FakeCloudLanguageStore())
        let service = GatewayService(
            host: "gateway.test", transport: FakeCloudSpeechTransport([.respond(status: 200, body: answer)]),
            proofs: NoProof(), languages: languages, fixedToken: "staging")
        let capabilities = try await service.capabilities()
        #expect(capabilities.languages == ["te", "hi"], "a language is offered only when it can be transcribed")
        #expect(languages.languages == ["te", "hi"])
    }

    private struct NoProof: SubscriptionProofProviding {
        func signedTransaction() async -> String? { nil }
    }

    // MARK: Local models are unchanged

    @Test func onDeviceDetectionAndModelLanguagesAreUnchanged() {
        #expect(SpokenLanguages.detectionCandidates == ["en", "hi", "te"])
        #expect(ModelCatalog.multilingualLanguages == ["en", "hi", "te"])
        #expect(SpokenLanguages.cloudCandidates.map(\.code) == ["te", "hi", "ta", "kn", "ml"])
    }
}
