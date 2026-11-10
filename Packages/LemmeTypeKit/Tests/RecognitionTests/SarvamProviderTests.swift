import Domain
import Foundation
import Recognition
import TestSupport
import Testing

/// Sarvam's request and response formats, against the published API reference.
struct SarvamProviderTests {
    /// The response shape from Sarvam's speech-to-text reference.
    static let success = Data(
        #"{"request_id":"20241115_1","transcript":"రేపు team meeting ఉంది","language_code":"te-IN"}"#.utf8)
    static let clip = CloudAudioClip(wav: Data("wav-bytes".utf8), seconds: 2)
    let provider = SarvamProvider(makeBoundary: { "BOUNDARY" })

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
        #expect(CloudSpeechProviderContract.verify(provider, fixture: fixture).isEmpty)
    }

    @Test func transcribingAsksForCodeMixedTelugu() throws {
        let request = try provider.request(
            for: Self.clip, need: RecognitionNeed(language: "te"), credential: CloudCredential(secret: "k"))
        #expect(request.url.absoluteString == "https://api.sarvam.ai/speech-to-text")
        #expect(request.headers["api-subscription-key"] == "k")
        #expect(request.headers["Content-Type"] == "multipart/form-data; boundary=BOUNDARY")
        let text = body(of: request)
        #expect(text.contains("name=\"model\"\r\n\r\nsaaras:v4\r\n"))
        #expect(text.contains("name=\"mode\"\r\n\r\ncodemix\r\n"))
        #expect(text.contains("name=\"language_code\"\r\n\r\nte-IN\r\n"))
        #expect(text.contains("name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\nwav-bytes\r\n"))
        #expect(text.hasSuffix("--BOUNDARY--\r\n"))
    }

    @Test func translatingAsksForEnglish() throws {
        let request = try provider.request(
            for: Self.clip, need: RecognitionNeed(language: "te", task: .translateToEnglish),
            credential: CloudCredential(secret: "k"))
        #expect(body(of: request).contains("name=\"mode\"\r\n\r\ntranslate\r\n"))
    }

    @Test func automaticLanguageAsksSarvamToDetectAndTranslates() throws {
        let request = try provider.request(
            for: Self.clip, need: RecognitionNeed(language: SpokenLanguages.automatic, task: .translateToEnglish),
            credential: CloudCredential(secret: "k"))
        let text = body(of: request)
        #expect(text.contains("name=\"language_code\"\r\n\r\nunknown\r\n"))
        #expect(text.contains("name=\"mode\"\r\n\r\ntranslate\r\n"))
        #expect(provider.detectsLanguage)
    }

    @Test func onlyTeluguIsOfferedForNow() {
        #expect(provider.supportedLanguages == ["te"])
        #expect(throws: RecognitionError.unsupported(.language)) {
            try provider.request(
                for: Self.clip, need: RecognitionNeed(language: "en-US"), credential: CloudCredential(secret: "k"))
        }
    }

    @Test func sarvamsErrorCodeDecidesBeforeTheStatus() {
        func envelope(_ code: String) -> String { #"{"error":{"message":"details","code":"\#(code)"}}"# }
        #expect(error(status: 429, body: envelope("insufficient_quota_error")) == .cloudQuotaExhausted)
        #expect(error(status: 400, body: envelope("invalid_api_key_error")) == .cloudKeyRejected)
        #expect(error(status: 400, body: envelope("rate_limit_exceeded_error")) == .cloudRateLimited)
        #expect(error(status: 400, body: envelope("invalid_request_error")) == .cloudServiceFailed)
    }

    @Test func statusDecidesWhenTheBodyIsUnreadable() {
        #expect(error(status: 403, body: "<html>") == .cloudKeyRejected)
        #expect(error(status: 402, body: "<html>") == .cloudQuotaExhausted)
        #expect(error(status: 429, body: "<html>") == .cloudRateLimited)
        #expect(error(status: 502, body: "<html>") == .cloudServiceFailed)
    }
}
