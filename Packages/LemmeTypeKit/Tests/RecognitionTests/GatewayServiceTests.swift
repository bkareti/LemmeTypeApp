import Domain
import Foundation
import Recognition
import Synchronization
import TestSupport
import Testing

/// E13-S3: the access token is made from the subscription, kept in memory, and refreshed before it ends.
struct GatewayServiceTests {
    static let session = Data(
        #"{"accessToken":"token-A","expiresInSeconds":900,"plan":"paid","periodEnd":"2026-12-12T12:00:00.000Z","allowanceSeconds":7200,"usedSeconds":600}"#
            .utf8)
    static let capabilities = Data(
        #"{"app":"lemmetype","consentVersion":4,"maximumClipSeconds":30,"tasks":["transcribe"],"languages":[]}"#.utf8)
    static let usage = Data(
        #"{"plan":"paid","periodStart":"2026-11-12T12:00:00.000Z","periodEnd":"2026-12-12T12:00:00.000Z","allowanceSeconds":7200,"usedSeconds":1200,"remainingSeconds":6000}"#
            .utf8)

    final class Clock: @unchecked Sendable {
        private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        var now: Date { value.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { value.withLock { $0.addTimeInterval(seconds) } }
    }

    final class Proof: SubscriptionProofProviding {
        private let signed: Mutex<String?>
        init(_ signed: String? = "SIGNED-TRANSACTION") { self.signed = Mutex(signed) }
        func signedTransaction() async -> String? { signed.withLock { $0 } }
        func set(_ value: String?) { signed.withLock { $0 = value } }
    }

    private func service(
        _ transport: FakeCloudSpeechTransport, proof: Proof = Proof(), clock: Clock = Clock(), fixed: String? = nil
    ) -> GatewayService {
        GatewayService(
            host: "gateway.test", transport: transport, proofs: proof, fixedToken: fixed, now: { clock.now })
    }

    private func respond(_ status: Int, _ body: Data = Data()) -> FakeCloudSpeechTransport.Step {
        .respond(status: status, body: body)
    }

    @Test func tradesTheSubscriptionForATokenAndReusesItUntilJustBeforeItEnds() async throws {
        let transport = FakeCloudSpeechTransport([respond(200, Self.session)])
        let clock = Clock()
        let service = service(transport, clock: clock)
        #expect(try await service.accessToken() == "token-A")
        #expect(try await service.accessToken() == "token-A")
        #expect(transport.requests.count == 1, "the second call used the cached token")
        let request = try #require(transport.requests.first)
        #expect(request.url.absoluteString == "https://gateway.test/v1/session")
        #expect(request.method == "POST")
        #expect(String(bytes: request.body, encoding: .utf8)?.contains("SIGNED-TRANSACTION") == true)
        #expect(request.headers["Authorization"] == nil, "the session route needs no token")

        clock.advance(900 - 30)  // inside the one-minute margin
        _ = try await service.accessToken()
        #expect(transport.requests.count == 2, "a new token was fetched before the old one ended")
    }

    @Test func withoutASubscriptionNothingIsSent() async {
        let transport = FakeCloudSpeechTransport([respond(200, Self.session)])
        let service = service(transport, proof: Proof(nil))
        await #expect(throws: GatewayAccessError.subscriptionRequired) { try await service.accessToken() }
        #expect(await service.canObtainToken() == false)
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [(401, GatewayAccessError.subscriptionRequired), (402, .subscriptionRequired), (500, .failed)])
    func mapsTheGatewaysAnswerToOneError(status: Int, expected: GatewayAccessError) async {
        let service = service(FakeCloudSpeechTransport([respond(status, Data("{}".utf8))]))
        await #expect(throws: expected) { try await service.accessToken() }
    }

    @Test func reportsOfflineAndOtherTransportFailures() async {
        let offline = service(FakeCloudSpeechTransport([.fail(.offline)]))
        await #expect(throws: GatewayAccessError.offline) { try await offline.accessToken() }
        let broken = service(FakeCloudSpeechTransport([.fail(.timedOut)]))
        await #expect(throws: GatewayAccessError.failed) { try await broken.accessToken() }
    }

    @Test func discardingTheTokenMakesTheNextCallFetchANewOne() async throws {
        let transport = FakeCloudSpeechTransport([respond(200, Self.session)])
        let service = service(transport)
        _ = try await service.accessToken()
        await service.discardToken()
        _ = try await service.accessToken()
        #expect(transport.requests.count == 2)
    }

    @Test func readsTheTermsVersionWithTheTokenAndCachesItForAnHour() async throws {
        let transport = FakeCloudSpeechTransport([respond(200, Self.session), respond(200, Self.capabilities)])
        let clock = Clock()
        let service = service(transport, clock: clock)
        #expect(try await service.capabilities().consentVersion == 4)
        #expect(try await service.capabilities().consentVersion == 4)
        #expect(transport.requests.count == 2, "one session and one capabilities request")
        let read = try #require(transport.requests.last)
        #expect(read.url.absoluteString == "https://gateway.test/v1/capabilities")
        #expect(read.method == "GET")
        #expect(read.headers["Authorization"] == "Bearer token-A")
        #expect(read.body.isEmpty)
    }

    @Test func aRefusedTokenIsReplacedOnceForARead() async throws {
        let transport = FakeCloudSpeechTransport([
            respond(200, Self.session), respond(401, Data("{}".utf8)), respond(200, Self.session),
            respond(200, Self.capabilities),
        ])
        let service = service(transport)
        #expect(try await service.capabilities().consentVersion == 4)
        #expect(transport.requests.count == 4, "session, refused read, new session, read again")
    }

    @Test func theAllowanceComesFromTheSessionAndThenFromUsage() async throws {
        let transport = FakeCloudSpeechTransport([respond(200, Self.session), respond(200, Self.usage)])
        let service = service(transport)
        _ = try await service.accessToken()
        let current = try #require(await service.allowance())
        #expect(current.allowanceSeconds == 7200)
        #expect(current.usedSeconds == 1200)
        #expect(current.remainingMinutes == 100)
    }

    @Test func theAllowanceIsNilWhenNothingCanBeFoundOut() async {
        let service = service(FakeCloudSpeechTransport([.fail(.offline)]))
        #expect(await service.allowance() == nil)
    }

    @Test func aFixedTokenForStagingNeverCallsTheSessionRoute() async throws {
        let transport = FakeCloudSpeechTransport([respond(200, Self.capabilities)])
        let service = service(transport, proof: Proof(nil), fixed: "staging-token")
        #expect(try await service.accessToken() == "staging-token")
        #expect(await service.canObtainToken())
        _ = try await service.capabilities()
        #expect(transport.requests.allSatisfy { $0.url.path != "/v1/session" })
    }

    @Test func theTokenAppearsInNoDescription() async throws {
        let transport = FakeCloudSpeechTransport([respond(200, Self.session)])
        _ = try await service(transport).accessToken()
        let seen = transport.requests.map { String(describing: $0) + String(reflecting: $0) }.joined()
        #expect(!seen.contains("SIGNED-TRANSACTION"))
        #expect(!seen.contains("token-A"))
    }
}
