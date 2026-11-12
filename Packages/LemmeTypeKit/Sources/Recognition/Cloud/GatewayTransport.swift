import Domain

/// Adds the gateway access token to each request and, if the gateway refuses it, asks for a new one and
/// tries once more. The token lives only in memory and is never in a request the engine builds.
public struct GatewayTransport: CloudSpeechTransport {
    private let base: any CloudSpeechTransport
    private let access: any GatewayAccessing

    public init(base: any CloudSpeechTransport, access: any GatewayAccessing) {
        self.base = base
        self.access = access
    }

    public func send(_ request: CloudHTTPRequest) async throws(CloudTransportFailure) -> CloudHTTPResponse {
        let first = try await attempt(request)
        guard first.status == 401 else { return first }
        await access.discardToken()
        return try await attempt(request)
    }

    private func attempt(_ request: CloudHTTPRequest) async throws(CloudTransportFailure) -> CloudHTTPResponse {
        let token: String
        do throws(GatewayAccessError) {
            token = try await access.accessToken()
        } catch {
            switch error {
            case .subscriptionRequired: throw .subscriptionRequired
            case .offline: throw .offline
            case .failed: throw .failed
            }
        }
        var headers = request.headers
        headers["Authorization"] = "Bearer \(token)"
        return try await base.send(
            CloudHTTPRequest(url: request.url, method: request.method, headers: headers, body: request.body))
    }
}
