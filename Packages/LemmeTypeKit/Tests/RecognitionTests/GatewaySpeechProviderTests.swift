import Domain
import Foundation
import Recognition
import TestSupport
import Testing

/// The gateway's request and answers, against docs of the gateway (`openapi.yaml` in speech-gateway).
struct GatewaySpeechProviderTests {
    static let success = Data(
        #"{"text":"రేపు team meeting ఉంది","language":"te","durationSeconds":2,"requestId":"r1"}"#.utf8)
    static let clip = CloudAudioClip(wav: Data("wav-bytes".utf8), seconds: 2)
    let provider = GatewaySpeechProvider(host: "gateway.test", makeBoundary: { "BOUNDARY" })

    private func body(of request: CloudHTTPRequest) -> String {
        String(bytes: request.body, encoding: .utf8) ?? ""
    }

    private func error(status: Int, body: String) -> RecognitionError? {
        do {
            _ = try provider.transcript(from: CloudHTTPResponse(status: status, body: Data(body.utf8)))
            return nil
        } catch {
            return error
        }
    }

    @Test(arguments: [RecognitionTask.transcribe, .translateToEnglish])
    func passesTheProviderContract(task: RecognitionTask) {
        let fixture = CloudSpeechProviderContract.Fixture(
            need: RecognitionNeed(language: "te", task: task), successBody: Self.success,
            expectedText: "రేపు team meeting ఉంది")
        #expect(CloudSpeechProviderContract.verify(provider, fixture: fixture) == [])
    }

    @Test func sendsTheTaskAndLanguageAsFormFieldsToTheGatewayRoute() throws {
        let transcribe = try provider.request(
            for: Self.clip, need: RecognitionNeed(language: "te", task: .transcribe),
            credential: CloudCredential(secret: "placeholder"))
        #expect(transcribe.url.absoluteString == "https://gateway.test/v1/speech/transcriptions")
        #expect(transcribe.method == "POST")
        #expect(body(of: transcribe).contains("name=\"task\"\r\n\r\ntranscribe"))
        #expect(body(of: transcribe).contains("name=\"language\"\r\n\r\nte"))
        #expect(body(of: transcribe).contains("name=\"audio\"; filename=\"audio.wav\""))

        let translate = try provider.request(
            for: Self.clip, need: RecognitionNeed(language: "te", task: .translateToEnglish),
            credential: CloudCredential(secret: "placeholder"))
        #expect(body(of: translate).contains("name=\"task\"\r\n\r\ntranslate"))
    }

    @Test func sendsNothingButAudioTaskAndLanguage() throws {
        let request = try provider.request(
            for: Self.clip, need: RecognitionNeed(language: "te", task: .transcribe),
            credential: CloudCredential(secret: "placeholder"))
        let names = body(of: request).components(separatedBy: "form-data; name=\"").dropFirst().map {
            $0.prefix { $0 != "\"" }
        }
        #expect(names.map(String.init) == ["task", "language", "audio"], "no hints, context, or other fields")
    }

    @Test func doesNotGuessTheLanguage() {
        #expect(throws: RecognitionError.unsupported(.language)) {
            try provider.request(
                for: Self.clip, need: RecognitionNeed(language: SpokenLanguages.automatic, task: .transcribe),
                credential: CloudCredential(secret: "placeholder"))
        }
        #expect(throws: RecognitionError.unsupported(.language)) {
            try provider.request(
                for: Self.clip, need: RecognitionNeed(language: "hi", task: .transcribe),
                credential: CloudCredential(secret: "placeholder"))
        }
    }

    @Test(arguments: [
        (401, "unauthorized", RecognitionError.cloudKeyRejected),
        (402, "subscription_required", .subscriptionRequired),
        (429, "quota_exceeded", .cloudQuotaExhausted),
        (429, "rate_limited", .cloudRateLimited),
        (503, "provider_busy", .cloudRateLimited),
        (422, "unsupported_language", .unsupported(.language)),
        (400, "audio_invalid", .cloudServiceFailed),
        (413, "audio_too_long", .cloudServiceFailed),
        (400, "bad_request", .cloudServiceFailed),
        (502, "provider_unavailable", .cloudServiceFailed),
        (503, "service_unavailable", .cloudUnavailable),
    ])
    func mapsEachGatewayCodeToOneMessage(status: Int, code: String, expected: RecognitionError) {
        let body = #"{"error":{"code":"\#(code)","message":"CANARY-GATEWAY-MESSAGE"}}"#
        #expect(error(status: status, body: body) == expected)
        #expect(!String(describing: expected).contains("CANARY"), "the gateway's own words are never kept")
    }

    @Test func aSuccessWithAnEmptyTextMeansNoSpeech() throws {
        let text = try provider.transcript(
            from: CloudHTTPResponse(
                status: 200, body: Data(#"{"text":"","language":"te","durationSeconds":1,"requestId":"r"}"#.utf8)))
        #expect(text.isEmpty)
    }
}
