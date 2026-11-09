// The network path for opt-in cloud speech (docs/decisions/0031-cloud-speech-provider.md).
// It runs only for a session whose mode names the cloud engine, never in Local mode.
// The lint rule against network APIs is disabled for this file only.
// swiftlint:disable no_network_apis

import Domain
import Foundation

/// Sends a request to one host only: ephemeral session (no cookies, cache, or
/// stored credentials), HTTPS, and no redirects, so audio cannot be sent on
/// to anywhere the consent did not name.
public final class URLSessionCloudSpeechTransport: CloudSpeechTransport {
    private let session: URLSession
    private let allowedHost: String
    private let attemptTimeout: TimeInterval

    public init(
        allowedHost: String,
        attemptTimeout: TimeInterval = 20,
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = attemptTimeout
        configuration.timeoutIntervalForResource = attemptTimeout
        self.allowedHost = allowedHost
        self.attemptTimeout = attemptTimeout
        session = URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    public func send(_ request: CloudHTTPRequest) async throws(CloudTransportFailure) -> CloudHTTPResponse {
        guard request.url.scheme == "https", request.url.host() == allowedHost else { throw .hostRefused }
        var outgoing = URLRequest(
            url: request.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: attemptTimeout)
        outgoing.httpMethod = "POST"
        outgoing.allHTTPHeaderFields = request.headers
        outgoing.httpBody = request.body

        let body: Data
        let response: URLResponse
        do {
            (body, response) = try await session.data(for: outgoing)
        } catch {
            throw Self.failure(for: error)
        }
        guard let http = response as? HTTPURLResponse else { throw .failed }
        guard !(300...399).contains(http.statusCode), http.url?.host() == allowedHost else { throw .hostRefused }
        return CloudHTTPResponse(status: http.statusCode, body: body)
    }

    private static func failure(for error: any Error) -> CloudTransportFailure {
        if error is CancellationError { return .cancelled }
        switch (error as? URLError)?.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
            .dataNotAllowed, .internationalRoamingOff:
            return .offline
        default: return .failed
        }
    }
}

/// Declining every redirect hands the 3xx back to `send`, which refuses it.
private final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
// swiftlint:enable no_network_apis
