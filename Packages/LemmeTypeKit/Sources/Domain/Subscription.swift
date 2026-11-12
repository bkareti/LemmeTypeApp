import Foundation

/// Where a person's subscription stands (E13-S4, ADR 0034). Derived from StoreKit, never stored.
public enum SubscriptionState: Equatable, Sendable {
    /// StoreKit has not answered yet.
    case unknown
    case notSubscribed
    /// In the free trial.
    case trialing(until: Date)
    /// Paying. `willRenew` is false after the person turned renewal off but before it ends.
    case subscribed(renews: Date?, willRenew: Bool)
    /// A renewal payment failed, and Apple still gives access for a while.
    case gracePeriod(until: Date)
    /// A renewal payment failed and access has stopped while Apple keeps trying.
    case billingRetry
    case expired(ended: Date)
    /// Refunded or revoked by Apple.
    case revoked

    /// Whether this state lets the person use the app. E13-S5 decides what that allows.
    public var grantsAccess: Bool {
        switch self {
        case .trialing, .subscribed, .gracePeriod: true
        case .unknown, .notSubscribed, .billingRetry, .expired, .revoked: false
        }
    }
}

/// A length of time StoreKit reports for a subscription or its trial. The numbers come from StoreKit.
public struct SubscriptionLength: Equatable, Sendable {
    public enum Unit: Equatable, Sendable {
        case day, week, month, year
    }

    public let value: Int
    public let unit: Unit

    public init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }
}

/// What the paywall shows. Every field is read from StoreKit.
public struct SubscriptionProduct: Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// The price, already formatted for the person's storefront ("$1.99").
    public let displayPrice: String
    public let period: SubscriptionLength
    /// The free trial this Apple ID can still get, or `nil` when it has used it or there is none.
    public let freeTrial: SubscriptionLength?

    public init(
        id: String, displayName: String, displayPrice: String, period: SubscriptionLength,
        freeTrial: SubscriptionLength?
    ) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.period = period
        self.freeTrial = freeTrial
    }
}

/// How an attempt to subscribe ended.
public enum PurchaseOutcome: Equatable, Sendable {
    case purchased
    /// Waiting for someone else to approve (Ask to Buy) or for the bank.
    case pending
    /// The person closed Apple's sheet.
    case cancelled
    /// Apple answered, but the signature did not check out, so nothing was granted.
    case unverified
    case failed
}

/// The subscription, as the app sees it. `StoreKitSubscriptionService` is the real one.
public protocol SubscriptionProviding: Sendable {
    /// Loads the product and the state, and starts listening for changes. Safe to call more than once.
    func start() async
    func product() async -> SubscriptionProduct?
    func currentState() async -> SubscriptionState
    /// A new stream of every state change from now on.
    var stateUpdates: AsyncStream<SubscriptionState> { get }
    func purchase() async -> PurchaseOutcome
    /// Asks the App Store about this Apple ID's purchases. `true` when a subscription that grants access was found.
    func restore() async -> Bool
    /// Shows Apple's screen for changing or cancelling the subscription.
    func showManageSubscriptions() async
}

/// Whether the paywall has already been shown on its own once, so it is not forced on the person again.
public protocol PaywallSeenStoring: AnyObject, Sendable {
    var hasSeenPaywall: Bool { get set }
}
