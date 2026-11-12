import Foundation

/// Why dictation is not allowed.
public enum EntitlementBlockReason: String, Equatable, Sendable {
    /// No trial or subscription.
    case noSubscription = "no-subscription"
    /// The trial or subscription ended.
    case expired
    case revoked
    /// A renewal payment failed.
    case paymentProblem = "payment-problem"
    /// StoreKit has not said yet whether there is a subscription.
    case unconfirmed
}

/// Whether the person may dictate right now (E13-S5, ADR 0034).
public enum EntitlementDecision: Equatable, Sendable {
    case allowed
    /// The period has ended, and the App Store could not be reached to confirm a renewal, so access continues
    /// for a short while longer.
    case allowedUnconfirmed(until: Date)
    case blocked(EntitlementBlockReason)

    public var allowsDictation: Bool {
        switch self {
        case .allowed, .allowedUnconfirmed: true
        case .blocked: false
        }
    }
}

/// The one rule for "may this person dictate", applied the same way by every way of starting a dictation.
///
/// It is pure: the subscription state, the time, and the latest moment the device has ever seen go in, a
/// decision comes out. Dictation is not blocked while the App Store is unreachable: StoreKit keeps verified
/// transactions on the device, so Local dictation needs no network.
public enum EntitlementPolicy {
    /// How long after a period ends, with no way to reach the App Store, a renewal is assumed (proposed in E13-S5).
    public static let unconfirmedGrace: TimeInterval = 3 * 24 * 60 * 60

    /// - Parameters:
    ///   - state: Where the subscription stands, from StoreKit.
    ///   - now: The device's clock.
    ///   - highWaterMark: The latest time this device has ever seen. A clock set back is never taken as more
    ///     time: the later of the two counts.
    ///   - appStoreReachable: Whether the App Store answered just now. When it did, an ended period is ended.
    /// - Returns: Whether dictation is allowed, allowed on trust for a short while, or blocked and why.
    public static func decide(
        state: SubscriptionState, now: Date, highWaterMark: Date?, appStoreReachable: Bool
    ) -> EntitlementDecision {
        let moment = max(now, highWaterMark ?? now)
        func ending(at end: Date, reason: EntitlementBlockReason) -> EntitlementDecision {
            if moment < end { return .allowed }
            let limit = end.addingTimeInterval(unconfirmedGrace)
            if !appStoreReachable, moment < limit { return .allowedUnconfirmed(until: limit) }
            return .blocked(reason)
        }
        switch state {
        case .unknown: return .blocked(.unconfirmed)
        case .notSubscribed: return .blocked(.noSubscription)
        case .trialing(let until): return ending(at: until, reason: .expired)
        case .subscribed(let renews, _): return renews.map { ending(at: $0, reason: .expired) } ?? .allowed
        case .gracePeriod(let until): return moment < until ? .allowed : .blocked(.paymentProblem)
        case .billingRetry: return .blocked(.paymentProblem)
        case .expired(let ended): return ending(at: ended, reason: .expired)
        case .revoked: return .blocked(.revoked)
        }
    }
}

/// Asked before a dictation starts, so nothing is recorded for someone who may not dictate.
public protocol EntitlementChecking: Sendable {
    func decision() async -> EntitlementDecision
}

/// The latest moment the device has seen, kept so that setting the clock back does not give more time.
public protocol EntitlementLedgerStoring: AnyObject, Sendable {
    var highWaterMark: Date? { get set }
}

/// Reads the subscription and applies ``EntitlementPolicy``.
public struct EntitlementGate: EntitlementChecking {
    private let subscription: any SubscriptionProviding
    private let ledger: any EntitlementLedgerStoring
    private let now: @Sendable () -> Date

    public init(
        subscription: any SubscriptionProviding, ledger: any EntitlementLedgerStoring,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.subscription = subscription
        self.ledger = ledger
        self.now = now
    }

    public func decision() async -> EntitlementDecision {
        let state = await subscription.currentState()
        let moment = now()
        let seen = ledger.highWaterMark
        var decision = EntitlementPolicy.decide(
            state: state, now: moment, highWaterMark: seen, appStoreReachable: false)
        // Only an assumed renewal depends on the App Store: ask it, so an ended period really ends when it can.
        if case .allowedUnconfirmed = decision, await subscription.canReachAppStore() {
            decision = EntitlementPolicy.decide(
                state: state, now: moment, highWaterMark: seen, appStoreReachable: true)
        }
        ledger.highWaterMark = max(moment, seen ?? moment)
        return decision
    }
}

/// What the keyboard and the intents may know about the subscription, without StoreKit: its kind and when it
/// ends, and nothing that identifies a person, a purchase, or a device (E13-S5).
public struct EntitlementSummary: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case trial, active, grace, none
    }

    public let status: Status
    public let endsAt: Date?

    public init(status: Status, endsAt: Date?) {
        self.status = status
        self.endsAt = endsAt
    }

    public init(_ state: SubscriptionState) {
        switch state {
        case .trialing(let until): self.init(status: .trial, endsAt: until)
        case .subscribed(let renews, _): self.init(status: .active, endsAt: renews)
        case .gracePeriod(let until): self.init(status: .grace, endsAt: until)
        case .unknown, .notSubscribed, .billingRetry, .expired, .revoked: self.init(status: .none, endsAt: nil)
        }
    }
}

public protocol EntitlementSummaryStoring: Sendable {
    func write(_ summary: EntitlementSummary)
    func read() -> EntitlementSummary?
    func clear()
}
