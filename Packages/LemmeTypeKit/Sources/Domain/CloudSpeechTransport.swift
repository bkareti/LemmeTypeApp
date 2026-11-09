import Foundation

/// A prepared POST. Holds the user's API key and voice, so its description
/// names the host only.
public struct CloudHTTPRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let url: URL
    public let headers: [String: String]
    public let body: Data

    public init(url: URL, headers: [String: String], body: Data) {
        self.url = url
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
    case failed
}

/// Sends one request. The only path from the app to a cloud speech vendor.
public protocol CloudSpeechTransport: Sendable {
    func send(_ request: CloudHTTPRequest) async throws(CloudTransportFailure) -> CloudHTTPResponse
}
