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
        var capabilityCalls = 0
        var token = "test-token"
        var languages = ["te"]
    }

    private let state = Mutex(State())

    /// Where a real ``GatewayService`` would record the languages it read, if anywhere.
    private let languageSink: (@Sendable ([String]) -> Void)?

    public init(
        hasSubscription: Bool = true, consentVersion: Int = 1,
        recordLanguages: (@Sendable ([String]) -> Void)? = nil
    ) {
        languageSink = recordLanguages
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
    /// The languages the next capabilities answer lists.
    public func setLanguages(_ value: [String]) { state.withLock { $0.languages = value } }
    public func setAllowance(_ value: GatewayAllowance?) { state.withLock { $0.allowance = value } }
    public var tokensIssued: Int { state.withLock { $0.tokensIssued } }
    public var discards: Int { state.withLock { $0.discards } }
    public var capabilityCalls: Int { state.withLock { $0.capabilityCalls } }

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
        let answer = state.withLock { state -> State in
            state.capabilityCalls += 1
            return state
        }
        if let failure = answer.capabilitiesFail { throw failure }
        languageSink?(answer.languages)
        return GatewayCapabilities(
            consentVersion: answer.consentVersion, maximumClipSeconds: 30, languages: answer.languages)
    }

    public func allowance() async -> GatewayAllowance? { state.withLock { $0.allowance } }
}
