import Domain
import Foundation
import Recognition
import TestSupport
import Testing

/// E13-S3: the access token is added here, and a refused one is replaced once.
struct GatewayTransportTests {
    private let request = CloudHTTPRequest(
        url: URL(string: "https://gateway.test/v1/speech/transcriptions")!, headers: ["Content-Type": "x"],
        body: Data("audio".utf8))

    @Test func addsTheTokenToTheRequest() async throws {
        let base = FakeCloudSpeechTransport([.respond(status: 200, body: Data())])
        let transport = GatewayTransport(base: base, access: FakeGatewayAccess())
        _ = try await transport.send(request)
        #expect(base.requests.first?.headers["Authorization"] == "Bearer test-token-1")
        #expect(base.requests.first?.headers["Content-Type"] == "x")
        #expect(base.requests.first?.body == Data("audio".utf8))
    }

    @Test func aRefusedTokenIsReplacedAndTheRequestSentOnceMore() async throws {
        let access = FakeGatewayAccess()
        let base = FakeCloudSpeechTransport([
            .respond(status: 401, body: Data()), .respond(status: 200, body: Data("ok".utf8)),
        ])
        let response = try await GatewayTransport(base: base, access: access).send(request)
        #expect(response.status == 200)
        #expect(access.discards == 1)
        #expect(base.requests.map { $0.headers["Authorization"] } == ["Bearer test-token-1", "Bearer test-token-2"])
    }

    @Test func aSecondRefusalIsPassedOnWithoutLooping() async throws {
        let base = FakeCloudSpeechTransport([.respond(status: 401, body: Data())])
        let response = try await GatewayTransport(base: base, access: FakeGatewayAccess()).send(request)
        #expect(response.status == 401)
        #expect(base.requests.count == 2, "one retry, no more")
    }

    @Test func withoutASubscriptionNothingIsSent() async {
        let base = FakeCloudSpeechTransport([.respond(status: 200, body: Data())])
        let transport = GatewayTransport(base: base, access: FakeGatewayAccess(hasSubscription: false))
        await #expect(throws: CloudTransportFailure.subscriptionRequired) { try await transport.send(request) }
        #expect(base.requests.isEmpty)
    }
}
