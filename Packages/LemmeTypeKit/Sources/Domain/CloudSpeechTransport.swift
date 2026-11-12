import Foundation

/// A prepared request. Holds the user's voice and access token, so its description
/// names the host only.
public struct CloudHTTPRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data

    public init(url: URL, method: String = "POST", headers: [String: String], body: Data = Data()) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }

    public var description: String { "CloudHTTPRequest(\(url.host() ?? "no host"))" }
    public var debugDescription: String { description }
}

/// What came back. The body can hold dictated text.
public struct CloudHTTPResponse: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public var description: String { "CloudHTTPResponse(\(status))" }
    public var debugDescription: String { description }
}

/// Why a request produced no response.
public enum CloudTransportFailure: Error, Equatable, Sendable {
    case cancelled
    case offline
    case timedOut
    /// The request or a redirect pointed somewhere other than the provider's host.
    case hostRefused
    /// There is no subscription to show the gateway (E13-S3).
    case subscriptionRequired
    case failed
}

/// Sends one request. The only path from the app to a cloud speech vendor.
public protocol CloudSpeechTransport: Sendable {
    func send(_ request: CloudHTTPRequest) async throws(CloudTransportFailure) -> CloudHTTPResponse
}
