import Domain
import Foundation
import Synchronization

/// A gateway that needs no network: it hands out a fixed token and can be told what to answer.
public final class FakeGatewayAccess: GatewayAccessing, GatewayCapabilitiesProviding, GatewayAllowanceProviding,
    SubscriptionProofProviding
{
    private struct State {
        var hasSubscription = true
        var consentVersion = 1
        var capabilitiesFail: GatewayAccessError?
        var allowance: GatewayAllowance?
        var tokensIssued = 0
        var discards = 0
        var token = "test-token"
    }

    private let state = Mutex(State())

    public init(hasSubscription: Bool = true, consentVersion: Int = 1) {
        state.withLock {
            $0.hasSubscription = hasSubscription
            $0.consentVersion = consentVersion
        }
    }

    public func setHasSubscription(_ value: Bool) { state.withLock { $0.hasSubscription = value } }
    public func setConsentVersion(_ value: Int) { state.withLock { $0.consentVersion = value } }
    public func setCapabilitiesFailure(_ failure: GatewayAccessError?) {
        state.withLock { $0.capabilitiesFail = failure }
    }
    public func setAllowance(_ value: GatewayAllowance?) { state.withLock { $0.allowance = value } }
    public var tokensIssued: Int { state.withLock { $0.tokensIssued } }
    public var discards: Int { state.withLock { $0.discards } }

    public func accessToken() async throws(GatewayAccessError) -> String {
        let result = state.withLock { state -> String? in
            guard state.hasSubscription else { return nil }
            state.tokensIssued += 1
            return "\(state.token)-\(state.tokensIssued)"
        }
        guard let result else { throw .subscriptionRequired }
        return result
    }

    public func discardToken() async { state.withLock { $0.discards += 1 } }
    public func canObtainToken() async -> Bool { state.withLock { $0.hasSubscription } }
    public func signedTransaction() async -> String? {
        state.withLock { $0.hasSubscription ? "signed-transaction" : nil }
    }

    public func capabilities() async throws(GatewayAccessError) -> GatewayCapabilities {
        let (failure, version) = state.withLock { ($0.capabilitiesFail, $0.consentVersion) }
        if let failure { throw failure }
        return GatewayCapabilities(consentVersion: version, maximumClipSeconds: 30)
    }

    public func allowance() async -> GatewayAllowance? { state.withLock { $0.allowance } }
}
