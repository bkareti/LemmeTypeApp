import Domain
import Foundation
import TestSupport
import Testing

/// E13-S5: one rule for "may this person dictate", pure, with the offline grace and the clock guard.
struct EntitlementPolicyTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400
    var end: Date { start.addingTimeInterval(7 * day) }

    private func decide(
        _ state: SubscriptionState, at now: Date? = nil, seen: Date? = nil, reachable: Bool = true
    ) -> EntitlementDecision {
        EntitlementPolicy.decide(state: state, now: now ?? start, highWaterMark: seen, appStoreReachable: reachable)
    }

    @Test func aTrialOrSubscriptionInsideItsPeriodIsAllowed() {
        #expect(decide(.trialing(until: end)) == .allowed)
        #expect(decide(.subscribed(renews: end, willRenew: true)) == .allowed)
        #expect(decide(.subscribed(renews: end, willRenew: false)) == .allowed)
        #expect(decide(.subscribed(renews: nil, willRenew: true)) == .allowed)
    }

    @Test func theLastSecondIsAllowedAndTheNextIsNot() {
        let lastSecond = end.addingTimeInterval(-1)
        #expect(decide(.trialing(until: end), at: lastSecond) == .allowed)
        #expect(decide(.trialing(until: end), at: end) == .blocked(.expired), "the end itself is outside the period")
        #expect(decide(.subscribed(renews: end, willRenew: true), at: end) == .blocked(.expired))
    }

    @Test func aGracePeriodAllowsUntilItEnds() {
        let until = start.addingTimeInterval(16 * day)
        #expect(decide(.gracePeriod(until: until)) == .allowed)
        #expect(decide(.gracePeriod(until: until), at: until.addingTimeInterval(-1)) == .allowed)
        #expect(decide(.gracePeriod(until: until), at: until) == .blocked(.paymentProblem))
    }

    @Test func everyStateThatGrantsNothingIsBlockedForItsOwnReason() {
        #expect(decide(.unknown) == .blocked(.unconfirmed))
        #expect(decide(.notSubscribed) == .blocked(.noSubscription))
        #expect(decide(.billingRetry) == .blocked(.paymentProblem))
        #expect(decide(.revoked) == .blocked(.revoked))
        #expect(decide(.expired(ended: start.addingTimeInterval(-day))) == .blocked(.expired))
    }

    @Test func withTheAppStoreOutOfReachAnEndedPeriodIsAssumedRenewedForThreeDays() {
        let limit = end.addingTimeInterval(EntitlementPolicy.unconfirmedGrace)
        #expect(EntitlementPolicy.unconfirmedGrace == 3 * day)
        #expect(
            decide(.trialing(until: end), at: end, reachable: false) == .allowedUnconfirmed(until: limit),
            "unconfirmed, not blocked")
        #expect(
            decide(.expired(ended: end), at: end.addingTimeInterval(day), reachable: false)
                == .allowedUnconfirmed(until: limit))
        #expect(decide(.expired(ended: end), at: limit.addingTimeInterval(-1), reachable: false).allowsDictation)
        #expect(decide(.expired(ended: end), at: limit, reachable: false) == .blocked(.expired), "three days, no more")
    }

    @Test func whenTheAppStoreAnswersAnEndedPeriodIsEnded() {
        #expect(decide(.expired(ended: end), at: end.addingTimeInterval(day), reachable: true) == .blocked(.expired))
        #expect(decide(.trialing(until: end), at: end, reachable: true) == .blocked(.expired))
    }

    @Test func aPaymentProblemIsNeverAssumedRenewed() {
        #expect(decide(.billingRetry, reachable: false) == .blocked(.paymentProblem))
        let until = start.addingTimeInterval(day)
        #expect(decide(.gracePeriod(until: until), at: until, reachable: false) == .blocked(.paymentProblem))
    }

    /// Setting the device clock back gives no more time: the latest moment ever seen counts.
    @Test func aClockSetBackThirtyDaysDoesNotExtendAccess() {
        let trialEnd = start.addingTimeInterval(-1)
        let rolledBack = start.addingTimeInterval(-30 * day)
        #expect(
            decide(.trialing(until: trialEnd), at: rolledBack, seen: nil) == .allowed, "nothing to compare with yet")
        #expect(
            decide(.trialing(until: trialEnd), at: rolledBack, seen: start) == .blocked(.expired),
            "the device has already seen \(start), so it is not earlier than that")
        #expect(
            decide(.subscribed(renews: trialEnd, willRenew: true), at: rolledBack, seen: start).allowsDictation == false
        )
    }

    @Test func aMarkEarlierThanNowChangesNothing() {
        #expect(decide(.trialing(until: end), at: start, seen: start.addingTimeInterval(-day)) == .allowed)
    }

    @Test func onlyAllowedDecisionsAllowDictation() {
        #expect(EntitlementDecision.allowed.allowsDictation)
        #expect(EntitlementDecision.allowedUnconfirmed(until: end).allowsDictation)
        #expect(!EntitlementDecision.blocked(.expired).allowsDictation)
    }
}

/// E13-S5: the gate reads the subscription and keeps the high-water mark.
struct EntitlementGateTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ value: Date) { self.value = value }
        var now: Date { lock.withLock { value } }
        func set(_ date: Date) { lock.withLock { value = date } }
    }

    private func gate(
        _ subscription: FakeSubscriptionService, ledger: FakeEntitlementLedger, clock: Clock
    ) -> EntitlementGate {
        EntitlementGate(subscription: subscription, ledger: ledger, now: { clock.now })
    }

    @Test func aTrialIsAllowedAndTheLedgerRemembersTheMoment() async {
        let clock = Clock(start)
        let ledger = FakeEntitlementLedger()
        let service = FakeSubscriptionService(state: .trialing(until: start.addingTimeInterval(7 * day)))
        #expect(await gate(service, ledger: ledger, clock: clock).decision() == .allowed)
        #expect(ledger.highWaterMark == start)
    }

    @Test func settingTheClockBackAfterTheTrialEndedDoesNotBringItBack() async {
        let clock = Clock(start.addingTimeInterval(8 * day))
        let ledger = FakeEntitlementLedger()
        let service = FakeSubscriptionService(state: .trialing(until: start.addingTimeInterval(7 * day)))
        service.setReachable(true)
        let gate = gate(service, ledger: ledger, clock: clock)
        #expect(await gate.decision() == .blocked(.expired))

        clock.set(start)  // 8 days back
        #expect(await gate.decision() == .blocked(.expired), "the clock being earlier is not more time")
        #expect(ledger.highWaterMark == start.addingTimeInterval(8 * day), "the mark never moves back")
    }

    @Test func anEndedPeriodIsAssumedRenewedOnlyWhileTheAppStoreIsOutOfReach() async {
        let ended = start.addingTimeInterval(-day)
        let service = FakeSubscriptionService(state: .expired(ended: ended))
        let gate = gate(service, ledger: FakeEntitlementLedger(), clock: Clock(start))

        service.setReachable(false)
        let limit = ended.addingTimeInterval(EntitlementPolicy.unconfirmedGrace)
        #expect(await gate.decision() == .allowedUnconfirmed(until: limit))

        service.setReachable(true)
        #expect(await gate.decision() == .blocked(.expired), "the App Store answered: it really ended")
    }

    @Test func noSubscriptionIsBlocked() async {
        let service = FakeSubscriptionService(state: .notSubscribed)
        let gate = gate(service, ledger: FakeEntitlementLedger(), clock: Clock(start))
        #expect(await gate.decision() == .blocked(.noSubscription))
    }
}

/// E13-S5: what the keyboard and intents may know holds no identifier.
struct EntitlementSummaryTests {
    let end = Date(timeIntervalSince1970: 1_900_000_000)

    @Test func eachStateBecomesAKindAndAnEndDate() {
        #expect(EntitlementSummary(.trialing(until: end)) == EntitlementSummary(status: .trial, endsAt: end))
        #expect(EntitlementSummary(.subscribed(renews: end, willRenew: true)) == .init(status: .active, endsAt: end))
        #expect(EntitlementSummary(.gracePeriod(until: end)) == .init(status: .grace, endsAt: end))
        for state in [SubscriptionState.unknown, .notSubscribed, .billingRetry, .expired(ended: end), .revoked] {
            #expect(EntitlementSummary(state) == .init(status: .none, endsAt: nil))
        }
    }

    @Test func itHoldsNoAppleIDTransactionIDOrOtherIdentifier() throws {
        let data = try JSONEncoder().encode(EntitlementSummary(.trialing(until: end)))
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        #expect(keys == ["endsAt", "status"], "only the kind and the end date")
        let text = String(bytes: data, encoding: .utf8) ?? ""
        for forbidden in ["transaction", "originalTransactionId", "appleId", "email", "token", "device"] {
            #expect(!text.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func theFakeStoreKeepsAndClearsIt() {
        let store = FakeEntitlementSummaryStore()
        store.write(EntitlementSummary(.trialing(until: end)))
        #expect(store.read()?.status == .trial)
        store.clear()
        #expect(store.read() == nil)
    }
}
