import Domain
import Foundation

/// What every ``CloudSpeechProvider`` must do, so a replacement vendor is held
/// to the same rules. Returns human-readable violations; tests check that the
/// result is empty.
public enum CloudSpeechProviderContract {
    /// A successful answer in the vendor's own format.
    public struct Fixture: Sendable {
        public let need: RecognitionNeed
        public let successBody: Data
        public let expectedText: String

        public init(need: RecognitionNeed, successBody: Data, expectedText: String) {
            self.need = need
            self.successBody = successBody
            self.expectedText = expectedText
        }
    }

    private static let canaryKey = "canary-key-7f3a"
    private static let audio = Data("canary-audio-bytes".utf8)

    public static func verify(_ provider: any CloudSpeechProvider, fixture: Fixture) -> [String] {
        checkFacts(provider, need: fixture.need) + checkRequest(provider, need: fixture.need)
            + checkUnknownLanguage(provider) + checkResponses(provider, fixture: fixture)
    }

    static func checkFacts(_ provider: any CloudSpeechProvider, need: RecognitionNeed) -> [String] {
        var issues: [String] = []
        if !DiagnosticValue.isSafeIdentifier(provider.id.rawValue) { issues.append("id is not a stable identifier") }
        if provider.id == CloudSpeechProviderID(rawValue: RecognitionEngineID.cloud.rawValue) {
            issues.append("id must name the vendor, not the engine")
        }
        if provider.displayName.isEmpty { issues.append("no display name, which the consent shows") }
        if provider.host.isEmpty || provider.host.contains("/") { issues.append("host is not a bare host name") }
        if provider.maximumClipSeconds <= 0 { issues.append("maximum clip length is not positive") }
        if provider.supportedLanguages.isEmpty { issues.append("no supported language") }
        if !provider.tasks.contains(need.task) { issues.append("fixture task is not one the provider offers") }
        return issues
    }

    static func checkRequest(_ provider: any CloudSpeechProvider, need: RecognitionNeed) -> [String] {
        let clip = CloudAudioClip(wav: audio, seconds: 1)
        let request: CloudHTTPRequest
        do {
            request = try provider.request(for: clip, need: need, credential: CloudCredential(secret: canaryKey))
        } catch {
            return ["request failed with \(error.identifier)"]
        }
        var issues: [String] = []
        if request.url.scheme != "https" { issues.append("request is not HTTPS") }
        if request.url.host() != provider.host { issues.append("request goes to a host other than provider.host") }
        if request.url.absoluteString.contains(canaryKey) { issues.append("the key is in the URL") }
        if request.body.range(of: Data(canaryKey.utf8)) != nil { issues.append("the key is in the body") }
        if !request.headers.values.contains(where: { $0.contains(canaryKey) }) {
            issues.append("the key is not in a header")
        }
        if request.body.range(of: audio) == nil { issues.append("the audio is not in the body") }
        return issues
    }

    static func checkUnknownLanguage(_ provider: any CloudSpeechProvider) -> [String] {
        let clip = CloudAudioClip(wav: audio, seconds: 1)
        do {
            _ = try provider.request(
                for: clip, need: RecognitionNeed(language: "zz"), credential: CloudCredential(secret: canaryKey))
            return ["a request was built for a language the provider does not list"]
        } catch {
            return error == .unsupported(.language) ? [] : ["unknown language threw \(error.identifier)"]
        }
    }

    static func checkResponses(_ provider: any CloudSpeechProvider, fixture: Fixture) -> [String] {
        var issues: [String] = []
        do {
            let text = try provider.transcript(from: CloudHTTPResponse(status: 200, body: fixture.successBody))
            if text != fixture.expectedText { issues.append("the success fixture did not give the expected text") }
        } catch {
            issues.append("the success fixture threw \(error.identifier)")
        }
        let failures: [(Int, RecognitionError)] = [
            (401, .cloudKeyRejected), (403, .cloudKeyRejected), (429, .cloudRateLimited), (500, .cloudServiceFailed),
            (503, .cloudServiceFailed), (200, .cloudServiceFailed),
        ]
        for (status, expected) in failures {
            do {
                _ = try provider.transcript(from: CloudHTTPResponse(status: status, body: Data("not json".utf8)))
                issues.append("status \(status) with an unreadable body returned text")
            } catch {
                if error != expected { issues.append("status \(status) threw \(error.identifier)") }
            }
        }
        return issues
    }
}
