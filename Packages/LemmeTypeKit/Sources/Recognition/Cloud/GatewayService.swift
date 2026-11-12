import Domain
import Foundation

/// Talks to the gateway's own routes (docs/decisions/0033-speech-gateway.md): trades the subscription for a
/// 15-minute access token, and reads what the gateway allows. The token is held in memory only.
///
/// `transport` must be the plain transport, not ``GatewayTransport``, because this type is what gives
/// that one its token.
public actor GatewayService: GatewayAccessing, GatewayCapabilitiesProviding, GatewayAllowanceProviding {
    private static let refreshMargin: TimeInterval = 60
    private static let capabilitiesLifetime: TimeInterval = 60 * 60
    /// Long enough that opening Settings twice makes one request, short enough to stay close to the truth.
    private static let allowanceLifetime: TimeInterval = 30

    private let transport: any CloudSpeechTransport
    private let proofs: any SubscriptionProofProviding
    private let host: String
    private let now: @Sendable () -> Date
    /// A fixed token for testing against staging in Debug builds. `nil` in every build that ships.
    private let fixedToken: String?

    private var token: (value: String, expiresAt: Date)?
    private var cachedCapabilities: (value: GatewayCapabilities, fetchedAt: Date)?
    private var lastAllowance: (value: GatewayAllowance, fetchedAt: Date)?
    /// The token request in progress, so callers that arrive together share one.
    private var tokenRequest: Task<String, any Error>?

    public init(
        host: String, transport: any CloudSpeechTransport, proofs: any SubscriptionProofProviding,
        fixedToken: String? = nil, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.host = host
        self.transport = transport
        self.proofs = proofs
        self.fixedToken = fixedToken
        self.now = now
    }

    // MARK: GatewayAccessing

    public func canObtainToken() async -> Bool {
        if fixedToken != nil || token != nil { return true }
        return await proofs.signedTransaction() != nil
    }

    public func discardToken() async {
        token = nil
    }

    public func accessToken() async throws(GatewayAccessError) -> String {
        if let fixedToken { return fixedToken }
        if let token, now() < token.expiresAt.addingTimeInterval(-Self.refreshMargin) { return token.value }
        if let tokenRequest { return try await result(of: tokenRequest) }
        let request = Task<String, any Error> { try await self.fetchToken() }
        tokenRequest = request
        defer { tokenRequest = nil }
        return try await result(of: request)
    }

    /// `Task` cannot carry a typed error, so anything other than ours is a plain failure.
    private func result(of request: Task<String, any Error>) async throws(GatewayAccessError) -> String {
        do {
            return try await request.value
        } catch {
            throw (error as? GatewayAccessError) ?? .failed
        }
    }

    private func fetchToken() async throws(GatewayAccessError) -> String {
        guard let signed = await proofs.signedTransaction() else { throw .subscriptionRequired }
        let body = (try? JSONEncoder().encode(["signedTransaction": signed])) ?? Data()
        let response = try await send(try request(path: "/v1/session", method: "POST", body: body, token: nil))
        switch response.status {
        case 200...299:
            guard let session = try? JSONDecoder().decode(Session.self, from: response.body) else { throw .failed }
            let lifetime = TimeInterval(session.expiresInSeconds)
            token = (session.accessToken, now().addingTimeInterval(lifetime))
            if let end = Self.date(session.periodEnd) {
                lastAllowance = (
                    GatewayAllowance(
                        allowanceSeconds: session.allowanceSeconds, usedSeconds: session.usedSeconds, periodEnd: end),
                    now()
                )
            }
            return session.accessToken
        case 401, 402: throw .subscriptionRequired
        default: throw .failed
        }
    }

    // MARK: GatewayCapabilitiesProviding

    public func capabilities() async throws(GatewayAccessError) -> GatewayCapabilities {
        if let cached = cachedCapabilities, now().timeIntervalSince(cached.fetchedAt) < Self.capabilitiesLifetime {
            return cached.value
        }
        let response = try await authorized(path: "/v1/capabilities")
        guard (200...299).contains(response.status),
            let answer = try? JSONDecoder().decode(Capabilities.self, from: response.body)
        else { throw response.status == 402 ? .subscriptionRequired : .failed }
        let value = GatewayCapabilities(
            consentVersion: answer.consentVersion, maximumClipSeconds: answer.maximumClipSeconds)
        cachedCapabilities = (value, now())
        return value
    }

    // MARK: GatewayAllowanceProviding

    public func allowance() async -> GatewayAllowance? {
        if let last = lastAllowance, now().timeIntervalSince(last.fetchedAt) < Self.allowanceLifetime {
            return last.value
        }
        guard let response = try? await authorized(path: "/v1/account/usage"), (200...299).contains(response.status),
            let usage = try? JSONDecoder().decode(Usage.self, from: response.body), let end = Self.date(usage.periodEnd)
        else { return lastAllowance?.value }
        let value = GatewayAllowance(
            allowanceSeconds: usage.allowanceSeconds, usedSeconds: usage.usedSeconds, periodEnd: end)
        lastAllowance = (value, now())
        return value
    }

    // MARK: Requests

    /// A GET with the access token; one fresh token is tried if the first is refused.
    private func authorized(path: String) async throws(GatewayAccessError) -> CloudHTTPResponse {
        var response = try await send(
            try request(path: path, method: "GET", body: Data(), token: try await accessToken()))
        if response.status == 401 {
            token = nil
            response = try await send(
                try request(path: path, method: "GET", body: Data(), token: try await accessToken()))
        }
        return response
    }

    private func request(
        path: String, method: String, body: Data, token: String?
    ) throws(GatewayAccessError) -> CloudHTTPRequest {
        guard let url = URL(string: "https://\(host)\(path)") else { throw .failed }
        var headers = ["Accept": "application/json"]
        if !body.isEmpty { headers["Content-Type"] = "application/json" }
        if let token { headers["Authorization"] = "Bearer \(token)" }
        return CloudHTTPRequest(url: url, method: method, headers: headers, body: body)
    }

    private func send(_ request: CloudHTTPRequest) async throws(GatewayAccessError) -> CloudHTTPResponse {
        do throws(CloudTransportFailure) {
            return try await transport.send(request)
        } catch {
            switch error {
            case .offline: throw .offline
            case .subscriptionRequired: throw .subscriptionRequired
            case .cancelled, .timedOut, .hostRefused, .failed: throw .failed
            }
        }
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private struct Session: Decodable {
        let accessToken: String
        let expiresInSeconds: Int
        let periodEnd: String
        let allowanceSeconds: Int
        let usedSeconds: Int
    }

    private struct Capabilities: Decodable {
        let consentVersion: Int
        let maximumClipSeconds: Double
    }

    private struct Usage: Decodable {
        let periodEnd: String
        let allowanceSeconds: Int
        let usedSeconds: Int
    }
}
