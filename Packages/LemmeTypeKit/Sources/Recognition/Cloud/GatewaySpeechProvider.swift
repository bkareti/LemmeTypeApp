import Domain
import Foundation

/// The LemmeType gateway (docs/decisions/0033-speech-gateway.md): the one place audio goes in Cloud
/// mode. The gateway holds the speech vendor's key, so the app holds none, and which vendor serves a
/// language is decided there. The credential is a placeholder: ``GatewayTransport`` puts the real access
/// token in the `Authorization` header just before sending, so this type never holds a token.
public struct GatewaySpeechProvider: CloudSpeechProvider {
    public let id = CloudSpeechProviderID(rawValue: "lemmetype-gateway")
    public let displayName = "LemmeType"
    public let host: String
    public let maximumClipSeconds = 30.0
    public let tasks: Set<RecognitionTask> = [.transcribe, .translateToEnglish]

    private let makeBoundary: @Sendable () -> String

    public init(host: String, makeBoundary: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.host = host
        self.makeBoundary = makeBoundary
    }

    /// Telugu first; the gateway's `/v1/capabilities` is the source of truth for what it serves.
    public var supportedLanguages: [String] { ["te"] }

    public func request(
        for clip: CloudAudioClip, need: RecognitionNeed, credential: CloudCredential
    ) throws(RecognitionError) -> CloudHTTPRequest {
        let language = SpokenLanguages.code(of: need.language)
        guard !SpokenLanguages.isAutomatic(need.language), supportedLanguages.contains(language) else {
            throw .unsupported(.language)
        }
        guard let url = URL(string: "https://\(host)/v1/speech/transcriptions") else { throw .cloudServiceFailed }
        let form = CloudMultipartForm(
            boundary: makeBoundary(),
            fields: [("task", need.task == .translateToEnglish ? "translate" : "transcribe"), ("language", language)],
            fileField: "audio", fileName: "audio.wav", fileType: "audio/wav", file: clip.wav)
        return CloudHTTPRequest(
            url: url, headers: ["Content-Type": form.contentType, "Authorization": "Bearer \(credential.secret)"],
            body: form.body)
    }

    public func transcript(from response: CloudHTTPResponse) throws(RecognitionError) -> String {
        guard (200...299).contains(response.status) else { throw Self.failure(for: response) }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: response.body) else {
            throw .cloudServiceFailed
        }
        return answer.text
    }

    /// The gateway's symbolic code decides first; its message is never read or kept.
    private static let errorsByCode: [String: RecognitionError] = [
        "unauthorized": .cloudKeyRejected,
        "subscription_required": .subscriptionRequired,
        "quota_exceeded": .cloudQuotaExhausted,
        "rate_limited": .cloudRateLimited,
        "provider_busy": .cloudRateLimited,
        "unsupported_language": .unsupported(.language),
        "bad_request": .cloudServiceFailed,
        "audio_invalid": .cloudServiceFailed,
        "audio_too_long": .cloudServiceFailed,
        "provider_unavailable": .cloudServiceFailed,
        "service_unavailable": .cloudServiceFailed,
    ]

    private static func failure(for response: CloudHTTPResponse) -> RecognitionError {
        if let code = (try? JSONDecoder().decode(Failure.self, from: response.body))?.error.code,
            let known = errorsByCode[code]
        {
            return known
        }
        switch response.status {
        case 401, 403: return .cloudKeyRejected
        case 402: return .subscriptionRequired
        case 429: return .cloudRateLimited
        default: return .cloudServiceFailed
        }
    }

    private struct Answer: Decodable {
        let text: String
    }

    private struct FailureDetails: Decodable {
        let code: String?
    }

    private struct Failure: Decodable {
        let error: FailureDetails
    }
}
