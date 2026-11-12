import Domain
import Foundation
import Testing

@testable import Subscriptions

/// E13-S4: what StoreKit reports becomes one plain state.
struct SubscriptionSnapshotTests {
    let end = Date(timeIntervalSince1970: 2_000_000_000)

    private func snapshot(
        _ kind: SubscriptionSnapshot.Kind, expiration: Date? = nil, trial: Bool = false, renews: Bool = true,
        grace: Date? = nil, purchased: Date = Date(timeIntervalSince1970: 1_900_000_000)
    ) -> SubscriptionSnapshot {
        SubscriptionSnapshot(
            kind: kind, expiration: expiration ?? end, isFreeTrial: trial, willRenew: renews, graceUntil: grace,
            purchased: purchased)
    }

    @Test func aFreeTrialIsTrialing() {
        #expect(snapshot(.subscribed, trial: true).state == .trialing(until: end))
    }

    @Test func aPaidPeriodIsSubscribedAndSaysWhetherItRenews() {
        #expect(snapshot(.subscribed).state == .subscribed(renews: end, willRenew: true))
        #expect(snapshot(.subscribed, renews: false).state == .subscribed(renews: end, willRenew: false))
    }

    @Test func aGracePeriodKeepsAccessUntilItEnds() {
        let graceEnd = end.addingTimeInterval(16 * 86_400)
        let state = snapshot(.inGracePeriod, grace: graceEnd).state
        #expect(state == .gracePeriod(until: graceEnd))
        #expect(state.grantsAccess)
        #expect(snapshot(.inGracePeriod).state == .gracePeriod(until: end), "falls back to the period's end")
    }

    @Test func billingRetryExpiredAndRevokedGrantNothing() {
        #expect(snapshot(.inBillingRetry).state == .billingRetry)
        #expect(snapshot(.expired).state == .expired(ended: end))
        #expect(snapshot(.revoked).state == .revoked)
        for kind in [SubscriptionSnapshot.Kind.inBillingRetry, .expired, .revoked] {
            #expect(!snapshot(kind).state.grantsAccess)
        }
    }

    @Test func aSubscriptionWithNoEndDateIsNotTrusted() {
        let none = SubscriptionSnapshot(
            kind: .subscribed, expiration: nil, isFreeTrial: false, willRenew: true, graceUntil: nil,
            purchased: end)
        #expect(none.state == .notSubscribed)
    }

    @Test func theMostRecentTransactionDecidesAndNoneMeansNotSubscribed() {
        #expect(SubscriptionSnapshot.state(of: []) == .notSubscribed)
        let old = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = Date(timeIntervalSince1970: 1_900_000_000)
        // An old subscribed period does not hide that the latest one has ended.
        let state = SubscriptionSnapshot.state(of: [
            snapshot(.subscribed, purchased: old), snapshot(.expired, purchased: recent),
        ])
        #expect(state == .expired(ended: end))
        // The latest one counts when it is the good one.
        let renewed = SubscriptionSnapshot.state(of: [
            snapshot(.expired, purchased: old), snapshot(.subscribed, purchased: recent),
        ])
        #expect(renewed == .subscribed(renews: end, willRenew: true))
    }

    @Test func betweenTransactionsFromTheSameMomentTheMoreUsefulStateWins() {
        let state = SubscriptionSnapshot.state(of: [snapshot(.expired), snapshot(.subscribed), snapshot(.revoked)])
        #expect(state == .subscribed(renews: end, willRenew: true))
        #expect(SubscriptionSnapshot.state(of: [snapshot(.revoked), snapshot(.expired)]) == .expired(ended: end))
    }

    @Test func onlyTrialingSubscribedAndGraceGrantAccess() {
        #expect(SubscriptionState.trialing(until: end).grantsAccess)
        #expect(SubscriptionState.subscribed(renews: end, willRenew: false).grantsAccess)
        #expect(!SubscriptionState.unknown.grantsAccess)
        #expect(!SubscriptionState.notSubscribed.grantsAccess)
    }
}
