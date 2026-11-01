// swiftlint:disable no_network_apis
import Domain
import Foundation
import Synchronization
import Testing

@testable import Updates

/// A transport stub: records the requests it sees and answers from a script.
/// Nothing leaves the process.
final class StubTransport: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body = Data()
        var contentLength: Int64?
        var redirectTo: URL?
        var failure: URLError.Code?
    }

    static let seen = Mutex<[URLRequest]>([])
    static let reply = Mutex(Reply())

    static func reset(_ reply: Reply) {
        seen.withLock { $0 = [] }
        self.reply.withLock { $0 = reply }
    }

    static func response(_ url: URL, _ status: Int, _ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)
            ?? HTTPURLResponse()
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
        if let target = reply.redirectTo {
            let response = Self.response(url, 302, ["Location": target.absoluteString])
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            // Like a real server, also answer with the redirect itself, which is what the
            // client receives when it declines to follow.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var headers: [String: String] = [:]
        if let length = reply.contentLength { headers["Content-Length"] = String(length) }
        let response = Self.response(url, reply.status, headers)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// E7-S3: what the update check sends, and what it accepts back.
@Suite(.serialized)
struct GitHubReleaseFeedTests {
    static func feed() -> GitHubReleaseFeed {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubTransport.self]
        return GitHubReleaseFeed(appVersion: "0.1.0", configuration: configuration)
    }

    static func payload(_ items: [[String: Any]]) -> Data {
        (try? JSONSerialization.data(withJSONObject: items)) ?? Data()
    }

    static var good: [[String: Any]] {
        [
            [
                "tag_name": "v0.3.0-beta.1",
                "html_url": "https://github.com/bkareti/LemmeTypeApp/releases/tag/v0.3.0-beta.1",
                "draft": false, "prerelease": true,
            ],
            [
                "tag_name": "v0.2.0", "html_url": "https://github.com/bkareti/LemmeTypeApp/releases/tag/v0.2.0",
                "draft": false, "prerelease": false,
            ],
            [
                "tag_name": "v0.9.0", "html_url": "https://github.com/bkareti/LemmeTypeApp/releases/tag/v0.9.0",
                "draft": true,
            ],
            ["tag_name": "nightly", "html_url": "https://github.com/bkareti/LemmeTypeApp/releases/tag/nightly"],
        ]
    }

    // MARK: Parsing

    @Test func parsesAGitHubReleaseList() throws {
        let releases = try GitHubReleaseFeed.parse(Self.payload(Self.good))
        #expect(
            releases.map(\.version.description) == ["0.3.0-beta.1", "0.2.0"], "drafts and non-version tags are dropped")
        #expect(releases.map(\.isPrerelease) == [true, false])
        #expect(releases[1].pageURL.absoluteString == "https://github.com/bkareti/LemmeTypeApp/releases/tag/v0.2.0")
    }

    @Test(arguments: [
        "https://evil.example.com/bkareti/LemmeTypeApp/releases/tag/v9.0.0",
        "http://github.com/bkareti/LemmeTypeApp/releases/tag/v9.0.0",
        "https://github.com.evil.example/bkareti/LemmeTypeApp/releases/tag/v9.0.0",
        "https://github.com/someone-else/LemmeTypeApp/releases/tag/v9.0.0",
        "https://github.com/bkareti/LemmeTypeApp/archive/v9.0.0.zip",
        "javascript:alert(1)",
    ])
    func aLinkOffTheProjectsReleasesPageIsUntrusted(link: String) {
        let body = Self.payload([["tag_name": "v9.0.0", "html_url": link, "draft": false]])
        #expect(throws: UpdateError.untrustedLink) { try GitHubReleaseFeed.parse(body) }
    }

    @Test(arguments: ["not json", "{}", "[1, 2]", #"{"message":"Not Found"}"#])
    func somethingElseIsABadResponse(body: String) {
        #expect(throws: UpdateError.badResponse) { try GitHubReleaseFeed.parse(Data(body.utf8)) }
    }

    @Test func aReleaseWithNoLinkIsUntrusted() {
        let body = Self.payload([["tag_name": "v1.0.0", "draft": false]])
        #expect(throws: UpdateError.untrustedLink) { try GitHubReleaseFeed.parse(body) }
    }

    // MARK: The request

    @Test func theRequestCarriesOnlyTheAllowedHeadersAndNothingElse() async throws {
        StubTransport.reset(.init(body: Self.payload(Self.good)))
        _ = try await Self.feed().releases()

        let request = try #require(StubTransport.seen.withLock { $0 }.first)
        #expect(request.url == GitHubReleaseFeed.endpoint)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/bkareti/LemmeTypeApp/releases?per_page=10")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil && request.httpBodyStream == nil)
        #expect(request.httpShouldHandleCookies == false)
        let headers = request.allHTTPHeaderFields ?? [:]
        #expect(Set(headers.keys) == GitHubReleaseFeed.allowedHeaders)
        #expect(headers["User-Agent"] == "LemmeType/0.1.0")
        #expect(headers["Accept"] == "application/vnd.github+json")
        #expect(headers["Cookie"] == nil && headers["Authorization"] == nil)
    }

    @Test func oneCheckIsOneRequest() async throws {
        StubTransport.reset(.init(body: Self.payload(Self.good)))
        _ = try await Self.feed().releases()
        #expect(StubTransport.seen.withLock { $0 }.count == 1)
    }

    // MARK: The answer

    @Test func noReleasesPublishedIsAnEmptyList() async throws {
        StubTransport.reset(.init(status: 404, body: Data(#"{"message":"Not Found"}"#.utf8)))
        #expect(try await Self.feed().releases().isEmpty)
    }

    @Test(arguments: [(403, UpdateError.rateLimited), (429, .rateLimited), (500, .badResponse), (301, .badResponse)])
    func httpStatusesMapToErrors(status: Int, expected: UpdateError) async {
        StubTransport.reset(.init(status: status))
        await #expect(throws: expected) { try await Self.feed().releases() }
    }

    @Test func aResponseOverTheLimitIsRefused() async {
        StubTransport.reset(.init(body: Data(repeating: 0x20, count: GitHubReleaseFeed.maximumBytes + 10)))
        await #expect(throws: UpdateError.tooLarge) { try await Self.feed().releases() }
    }

    @Test func aDeclaredLengthOverTheLimitIsRefusedBeforeReading() async {
        StubTransport.reset(.init(body: Data("[]".utf8), contentLength: Int64(GitHubReleaseFeed.maximumBytes) + 1))
        await #expect(throws: UpdateError.tooLarge) { try await Self.feed().releases() }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost])
    func connectionProblemsAreOffline(code: URLError.Code) async {
        StubTransport.reset(.init(failure: code))
        await #expect(throws: UpdateError.offline) { try await Self.feed().releases() }
    }

    @Test func aRedirectOffGitHubIsNotFollowed() async {
        StubTransport.reset(.init(redirectTo: URL(string: "https://evil.example.com/releases")))
        await #expect(throws: UpdateError.badResponse) { try await Self.feed().releases() }
        let hosts = StubTransport.seen.withLock { $0 }.compactMap { $0.url?.host }
        #expect(!hosts.contains("evil.example.com"), "no request went to the redirect target")
    }

    @Test func errorIdentifiersAreStableAndSafe() {
        let all: [UpdateError] = [.offline, .rateLimited, .badResponse, .tooLarge, .untrustedLink, .unknownVersion]
        #expect(
            all.map(\.identifier) == [
                "update.offline", "update.rate-limited", "update.bad-response", "update.too-large",
                "update.untrusted-link", "update.unknown-version",
            ])
        #expect(all.allSatisfy { DiagnosticValue.isSafeIdentifier($0.identifier) })
    }
}

// swiftlint:enable no_network_apis
