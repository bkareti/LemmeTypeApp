// swiftlint:disable no_network_apis
import Domain
import Foundation
import Recognition
import Synchronization
import Testing

/// Answers inside the process, so these tests never touch the network.
final class CloudTransportStub: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body = Data()
        var redirectTo: URL?
        var failure: URLError.Code?
    }

    static let seen = Mutex<[URLRequest]>([])
    static let reply = Mutex(Reply())

    static func reset(_ reply: Reply) {
        seen.withLock { $0 = [] }
        self.reply.withLock { $0 = reply }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.withLock { $0.append(request) }
        let reply = Self.reply.withLock { $0 }
        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        guard let url = request.url else { return }
        let headers = reply.redirectTo.map { ["Location": $0.absoluteString] } ?? [:]
        let status = reply.redirectTo == nil ? reply.status : 302
        let response =
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) ?? HTTPURLResponse()
        if let target = reply.redirectTo {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct URLSessionCloudSpeechTransportTests {
    static let host = "api.sarvam.ai"
    static let url = URL(string: "https://api.sarvam.ai/speech-to-text")!

    private func transport() -> URLSessionCloudSpeechTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudTransportStub.self]
        return URLSessionCloudSpeechTransport(allowedHost: Self.host, configuration: configuration)
    }

    private func request(_ url: URL = Self.url) -> CloudHTTPRequest {
        CloudHTTPRequest(url: url, headers: ["api-subscription-key": "k"], body: Data("audio".utf8))
    }

    private func failure(_ request: CloudHTTPRequest) async -> CloudTransportFailure? {
        do {
            _ = try await transport().send(request)
            return nil
        } catch {
            return error
        }
    }

    @Test func returnsTheStatusAndBody() async throws {
        CloudTransportStub.reset(.init(status: 429, body: Data("slow down".utf8)))
        let response = try await transport().send(request())
        #expect(response.status == 429)
        #expect(response.body == Data("slow down".utf8))
        let sent = try #require(CloudTransportStub.seen.withLock { $0.first })
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "api-subscription-key") == "k")
    }

    @Test func refusesAnotherHostWithoutContactingIt() async throws {
        CloudTransportStub.reset(.init())
        let elsewhere = try #require(URL(string: "https://evil.example.com/speech-to-text"))
        #expect(await failure(request(elsewhere)) == .hostRefused)
        #expect(CloudTransportStub.seen.withLock { $0.isEmpty })
    }

    @Test func refusesPlainHTTP() async throws {
        CloudTransportStub.reset(.init())
        let insecure = try #require(URL(string: "http://api.sarvam.ai/speech-to-text"))
        #expect(await failure(request(insecure)) == .hostRefused)
        #expect(CloudTransportStub.seen.withLock { $0.isEmpty })
    }

    @Test func refusesARedirectAndDoesNotFollowIt() async throws {
        let target = try #require(URL(string: "https://evil.example.com/collect"))
        CloudTransportStub.reset(.init(redirectTo: target))
        #expect(await failure(request()) == .hostRefused)
        let hosts = CloudTransportStub.seen.withLock { $0.map { $0.url?.host() } }
        #expect(hosts == [Self.host], "audio must never be sent to the redirect target")
    }

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, CloudTransportFailure.offline),
        (.cannotFindHost, .offline),
        (.networkConnectionLost, .offline),
        (.timedOut, .timedOut),
        (.badServerResponse, .failed),
        (.cancelled, .cancelled),
    ])
    func mapsNetworkFailures(code: URLError.Code, expected: CloudTransportFailure) async {
        CloudTransportStub.reset(.init(failure: code))
        #expect(await failure(request()) == expected)
    }
}
// swiftlint:enable no_network_apis
