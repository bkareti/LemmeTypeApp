import Domain
import Foundation

/// What StoreKit says about one subscription, reduced to the facts the state needs. Keeping this apart from
/// StoreKit's own types lets the mapping be tested with plain values (E13-S4).
struct SubscriptionSnapshot: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case subscribed, inGracePeriod, inBillingRetry, expired, revoked
    }

    let kind: Kind
    /// When the current paid period, or the trial, ends.
    let expiration: Date?
    /// Whether the current period is the free trial.
    let isFreeTrial: Bool
    let willRenew: Bool
    /// When the grace period ends, if Apple reports one.
    let graceUntil: Date?
    /// When this period's transaction was made. The most recent one describes where the person stands now.
    let purchased: Date

    /// How much a snapshot says about access: a subscription that works beats one in grace, and so on.
    var rank: Int {
        switch kind {
        case .subscribed: 5
        case .inGracePeriod: 4
        case .inBillingRetry: 3
        case .expired: 2
        case .revoked: 1
        }
    }

    var state: SubscriptionState {
        switch kind {
        case .subscribed:
            guard let expiration else { return .notSubscribed }
            return isFreeTrial ? .trialing(until: expiration) : .subscribed(renews: expiration, willRenew: willRenew)
        case .inGracePeriod:
            guard let until = graceUntil ?? expiration else { return .billingRetry }
            return .gracePeriod(until: until)
        case .inBillingRetry: return .billingRetry
        case .expired: return expiration.map { .expired(ended: $0) } ?? .notSubscribed
        case .revoked: return .revoked
        }
    }

    /// What the newest verified transaction says on its own, for when StoreKit cannot be asked for statuses (no
    /// network). `Transaction.currentEntitlements` leaves out an ended period, so without this a subscription that
    /// just ended offline would read as "never subscribed" and skip the offline grace (E13-S5).
    static func fromLatestTransaction(
        expiration: Date?, isFreeTrial: Bool, revoked: Bool, purchased: Date, now: Date
    ) -> SubscriptionSnapshot {
        let kind: Kind = revoked ? .revoked : (expiration.map { $0 > now } == true ? .subscribed : .expired)
        return SubscriptionSnapshot(
            kind: kind, expiration: expiration, isFreeTrial: isFreeTrial, willRenew: false, graceUntil: nil,
            purchased: purchased)
    }

    /// The state for several snapshots (a group can report more than one): the most recent transaction decides,
    /// and between equal ones the more useful state. No snapshots means "not subscribed".
    static func state(of snapshots: [SubscriptionSnapshot]) -> SubscriptionState {
        snapshots.max { ($0.purchased, $0.rank) < ($1.purchased, $1.rank) }?.state ?? .notSubscribed
    }
}
