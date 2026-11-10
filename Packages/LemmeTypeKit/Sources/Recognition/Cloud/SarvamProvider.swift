import Domain
import Foundation

/// Sarvam Saaras v4 (docs/decisions/0031-cloud-speech-provider.md). The only
/// file that knows Sarvam's API; replacing the vendor replaces this file.
public struct SarvamProvider: CloudSpeechProvider {
    public let id = CloudSpeechProviderID(rawValue: "sarvam")
    public let displayName = "Sarvam"
    public let host = "api.sarvam.ai"
    public let maximumClipSeconds = 30.0
    public let tasks: Set<RecognitionTask> = [.transcribe, .translateToEnglish]
    /// Sarvam works out the language when `language_code` is `unknown`.
    public let detectsLanguage = true

    /// BCP 47 language → Sarvam's `language_code`. Languages are added one at a
    /// time, each after it has been measured.
    private static let languageCodes = ["te": "te-IN"]
    /// Sarvam's value for "detect the language yourself".
    private static let automaticLanguageCode = "unknown"
    private static let model = "saaras:v4"

    private let makeBoundary: @Sendable () -> String

    public init(makeBoundary: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.makeBoundary = makeBoundary
    }

    public var supportedLanguages: [String] { Self.languageCodes.keys.sorted() }

    public func request(
        for clip: CloudAudioClip, need: RecognitionNeed, credential: CloudCredential
    ) throws(RecognitionError) -> CloudHTTPRequest {
        let languageCode: String
        if SpokenLanguages.isAutomatic(need.language) {
            languageCode = Self.automaticLanguageCode
        } else if let code = Self.languageCodes[SpokenLanguages.code(of: need.language)] {
            languageCode = code
        } else {
            throw .unsupported(.language)
        }
        guard let url = URL(string: "https://\(host)/speech-to-text") else { throw .cloudServiceFailed }
        // `codemix` keeps English words in English letters inside Telugu text.
        let mode = need.task == .translateToEnglish ? "translate" : "codemix"
        let form = CloudMultipartForm(
            boundary: makeBoundary(),
            fields: [("model", Self.model), ("mode", mode), ("language_code", languageCode)],
            fileField: "file", fileName: "audio.wav", fileType: "audio/wav", file: clip.wav)
        return CloudHTTPRequest(
            url: url,
            headers: ["api-subscription-key": credential.secret, "Content-Type": form.contentType],
            body: form.body)
    }

    public func transcript(from response: CloudHTTPResponse) throws(RecognitionError) -> String {
        guard (200...299).contains(response.status) else { throw Self.failure(for: response) }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: response.body) else {
            throw .cloudServiceFailed
        }
        return answer.transcript
    }

    /// Sarvam's symbolic code decides first; its message is never read or kept.
    private static func failure(for response: CloudHTTPResponse) -> RecognitionError {
        switch (try? JSONDecoder().decode(Failure.self, from: response.body))?.error.code {
        case "insufficient_quota_error": .cloudQuotaExhausted
        case "invalid_api_key_error", "authentication_error": .cloudKeyRejected
        case "rate_limit_exceeded_error": .cloudRateLimited
        default:
            switch response.status {
            case 401, 403: .cloudKeyRejected
            case 402: .cloudQuotaExhausted
            case 429: .cloudRateLimited
            default: .cloudServiceFailed
            }
        }
    }

    private struct Answer: Decodable {
        let transcript: String
    }

    private struct FailureDetails: Decodable {
        let code: String?
    }

    private struct Failure: Decodable {
        let error: FailureDetails
    }
}
