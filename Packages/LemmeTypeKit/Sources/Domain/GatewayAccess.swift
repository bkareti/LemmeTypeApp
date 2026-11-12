import Foundation

/// Why the gateway could not give an access token or an answer.
public enum GatewayAccessError: Error, Equatable, Sendable {
    /// No active trial or subscription to show.
    case subscriptionRequired
    case offline
    case failed
}

/// Gives a request to the LemmeType gateway the short-lived token it needs (ADR 0033). The token is
/// kept in memory only and never written to disk.
public protocol GatewayAccessing: Sendable {
    /// A token that is good now: the cached one, or a new one made from the subscription.
    func accessToken() async throws(GatewayAccessError) -> String
    /// Forgets the cached token because the gateway refused it.
    func discardToken() async
    /// Whether a subscription can be shown at all. Uses no network.
    func canObtainToken() async -> Bool
}

/// Where the subscription proof comes from: StoreKit's signed transaction (E13-S4).
public protocol SubscriptionProofProviding: Sendable {
    /// The signed transaction of the current subscription, or `nil` when there is none.
    func signedTransaction() async -> String?
}

/// What the gateway says about this app.
public struct GatewayCapabilities: Equatable, Sendable {
    /// Raised by the gateway when audio would go somewhere the user has not agreed to.
    public let consentVersion: Int
    public let maximumClipSeconds: Double

    public init(consentVersion: Int, maximumClipSeconds: Double) {
        self.consentVersion = consentVersion
        self.maximumClipSeconds = maximumClipSeconds
    }
}

public protocol GatewayCapabilitiesProviding: Sendable {
    func capabilities() async throws(GatewayAccessError) -> GatewayCapabilities
}

/// How much of this billing period's cloud speech allowance is used.
public struct GatewayAllowance: Equatable, Sendable {
    public let allowanceSeconds: Int
    public let usedSeconds: Int
    public let periodEnd: Date

    public init(allowanceSeconds: Int, usedSeconds: Int, periodEnd: Date) {
        self.allowanceSeconds = allowanceSeconds
        self.usedSeconds = usedSeconds
        self.periodEnd = periodEnd
    }

    public var remainingSeconds: Int { max(0, allowanceSeconds - usedSeconds) }
    public var remainingMinutes: Int { remainingSeconds / 60 }
}

public protocol GatewayAllowanceProviding: Sendable {
    /// The current allowance, or `nil` when it cannot be found out now. Never throws: it is only shown.
    func allowance() async -> GatewayAllowance?
}
