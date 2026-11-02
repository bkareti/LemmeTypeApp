// The update check's only network code (docs/decisions/0026-distribution-and-updates.md):
// one HTTPS GET for release metadata, started by the user or by the weekly
// check they turned on, never during dictation. It downloads no application
// code. The lint rule against network APIs is disabled for this file only.
// swiftlint:disable no_network_apis

import Domain
import Foundation
import Support

/// Reads the project's published releases from GitHub's API.
///
/// - One `GET` of the release list; no body, cookies, credentials, cache, or
///   identifiers. The only app-specific value is the version in `User-Agent`.
/// - Redirects are followed only within `api.github.com`.
/// - At most `maximumBytes` of response are read; a larger one is cancelled.
/// - Every release page link must be on this project's GitHub releases page.
public struct GitHubReleaseFeed: UpdateFeed {
    /// `https://api.github.com/repos/bkareti/LemmeTypeApp/releases?per_page=10`
    public static var endpoint: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/bkareti/LemmeTypeApp/releases"
        components.queryItems = [URLQueryItem(name: "per_page", value: "10")]
        return components.url ?? URL(fileURLWithPath: "/")
    }
    public static let releasePagePrefix = "https://github.com/bkareti/LemmeTypeApp/releases/"
    public static let maximumBytes = 1_048_576
    public static let requestTimeout: TimeInterval = 15
    /// The only headers a request carries (plus those the system adds to every web request).
    public static let allowedHeaders: Set<String> = ["Accept", "User-Agent", "X-GitHub-Api-Version"]

    private let configuration: URLSessionConfiguration
    private let userAgent: String

    /// `configuration` exists so tests can stub the transport; the settings that
    /// keep the request anonymous are applied here either way.
    public init(appVersion: String, configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.requestTimeout * 2
        self.configuration = configuration
        userAgent = "LemmeType/\(appVersion)"
    }

    /// The request exactly as it is sent.
    var request: URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    public func releases() async throws(UpdateError) -> [ReleaseInfo] {
        let collector = BoundedResponse(limit: Self.maximumBytes)
        let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let body: Data
        do {
            let (data, response) = try await collector.run(session.dataTask(with: request))
            switch response.statusCode {
            case 200: body = data
            case 404: return []
            case 403, 429: throw UpdateError.rateLimited
            default: throw UpdateError.badResponse
            }
        } catch let error as UpdateError {
            throw error
        } catch {
            throw .offline
        }
        return try Self.parse(body)
    }

    /// Turns GitHub's release list into releases. Drafts are dropped; tags that
    /// are not versions are skipped; a link off this project's releases page
    /// makes the whole answer untrusted.
    public static func parse(_ data: Data) throws(UpdateError) -> [ReleaseInfo] {
        let items: [ReleaseItem]
        do {
            items = try JSONDecoder().decode([ReleaseItem].self, from: data)
        } catch {
            throw .badResponse
        }
        var releases: [ReleaseInfo] = []
        for item in items where !item.isDraft {
            guard let tag = item.tag, let version = SemanticVersion(tag) else { continue }
            guard let link = item.link, link.hasPrefix(releasePagePrefix), let page = URL(string: link),
                page.scheme == "https", page.host == "github.com"
            else { throw .untrustedLink }
            releases.append(ReleaseInfo(version: version, pageURL: page, isPrerelease: item.isPrerelease))
        }
        return releases
    }
}

/// One entry of GitHub's release list; only the fields the check needs.
private struct ReleaseItem: Decodable {
    let tag: String?
    let link: String?
    let isDraft: Bool
    let isPrerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case link = "html_url"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        link = try container.decodeIfPresent(String.self, forKey: .link)
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        isPrerelease = try container.decodeIfPresent(Bool.self, forKey: .isPrerelease) ?? false
    }
}

/// Collects one response in chunks, stops at `limit` bytes, and follows
/// redirects only to `api.github.com` over HTTPS.
private final class BoundedResponse: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // The delegate callbacks and `run` touch this state from different threads; `lock` guards it.
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var response: HTTPURLResponse?
    private var overflowed = false
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>?

    init(limit: Int) {
        self.limit = limit
    }

    func run(_ task: URLSessionDataTask) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse else { return .cancel }
        let tooLarge = http.expectedContentLength > Int64(limit)
        lock.withLock {
            self.response = http
            overflowed = tooLarge
        }
        return tooLarge ? .cancel : .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let exceeded = lock.withLock { () -> Bool in
            data.append(chunk)
            if data.count > limit { overflowed = true }
            return overflowed
        }
        if exceeded { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let outcome:
            (CheckedContinuation<(Data, HTTPURLResponse), any Error>?, Result<(Data, HTTPURLResponse), any Error>) =
                lock.withLock {
                    let waiting = continuation
                    continuation = nil
                    if overflowed { return (waiting, .failure(UpdateError.tooLarge)) }
                    if let error { return (waiting, .failure(error)) }
                    guard let response else { return (waiting, .failure(UpdateError.badResponse)) }
                    return (waiting, .success((data, response)))
                }
        outcome.0?.resume(with: outcome.1)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard request.url?.scheme == "https", request.url?.host == "api.github.com" else { return nil }
        return request
    }
}

// swiftlint:enable no_network_apis
