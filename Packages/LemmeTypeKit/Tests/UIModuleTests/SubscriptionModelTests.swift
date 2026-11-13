import Domain
import Foundation
import TestSupport
import Testing

@testable import UI

/// E13-S4: the paywall's model shows only what the service reports and ends every attempt in plain words.
@MainActor
struct SubscriptionModelTests {
    let service = FakeSubscriptionService()
    let seen = FakePaywallSeen()
    let later = Date(timeIntervalSince1970: 4_000_000_000)

    private func makeModel() -> SubscriptionModel {
        SubscriptionModel(service: service, seen: seen)
    }

    @Test func startLoadsTheStateAndTheProductFromTheService() async {
        let model = makeModel()
        await model.start()
        #expect(model.state == .notSubscribed)
        #expect(model.product == FakeSubscriptionService.sampleProduct)
        #expect(service.starts == 1)
        model.stop()
    }

    @Test func somebodyWithNoSubscriptionSeesThePaywallOnceAndCanCloseIt() async {
        let model = makeModel()
        await model.start()
        #expect(model.isShowingPaywall)
        #expect(seen.hasSeenPaywall)
        model.isShowingPaywall = false

        let again = makeModel()
        await again.start()
        #expect(!again.isShowingPaywall, "it is not forced on the person a second time")
        again.showPaywall()
        #expect(again.isShowingPaywall, "it can still be opened on purpose")
        model.stop()
        again.stop()
    }

    @Test func aSubscriberIsNeverShownThePaywallOnItsOwn() async {
        let subscribed = FakeSubscriptionService(state: .subscribed(renews: later, willRenew: true))
        let model = SubscriptionModel(service: subscribed, seen: seen)
        await model.start()
        #expect(!model.isShowingPaywall)
        #expect(!seen.hasSeenPaywall)
        model.stop()
    }

    @Test func aTrialIsNotShownThePaywallEither() async {
        let trial = FakeSubscriptionService(state: .trialing(until: later))
        let model = SubscriptionModel(service: trial, seen: seen)
        await model.start()
        #expect(!model.isShowingPaywall)
        model.stop()
    }

    @Test func aLapsedSubscriptionIsOfferedTheWayBackOnce() async {
        let lapsed = FakeSubscriptionService(state: .expired(ended: later))
        let model = SubscriptionModel(service: lapsed, seen: seen)
        await model.start()
        #expect(model.isShowingPaywall)
        model.stop()
    }

    @Test func aPurchaseUnlocksAndClosesThePaywall() async {
        service.willPurchase(.purchased, leaving: .trialing(until: later))
        let model = makeModel()
        await model.start()
        await model.purchase()
        #expect(service.purchases == 1)
        #expect(model.state == .trialing(until: later))
        #expect(!model.isShowingPaywall)
        #expect(model.message == nil)
        model.stop()
    }

    @Test(arguments: [
        (PurchaseOutcome.cancelled, SubscriptionModel.Message.cancelled),
        (.pending, .pending), (.unverified, .unverified), (.failed, .failed),
    ])
    func everyOtherOutcomeLeavesTheAppLockedWithAPlainMessage(
        outcome: PurchaseOutcome, expected: SubscriptionModel.Message
    ) async {
        service.willPurchase(outcome)
        let model = makeModel()
        await model.start()
        await model.purchase()
        #expect(model.message == expected)
        #expect(!model.state.grantsAccess)
        #expect(model.isShowingPaywall, "the person stays where they were")
        #expect(!SubscriptionWording.message(expected).isEmpty)
        model.stop()
    }

    @Test func restoreFindsAnExistingSubscription() async {
        service.setRestoreFindsSubscription(true, leaving: .subscribed(renews: later, willRenew: true))
        let model = makeModel()
        await model.start()
        await model.restore()
        #expect(model.state == .subscribed(renews: later, willRenew: true))
        #expect(!model.isShowingPaywall)
        model.stop()
    }

    @Test func restoreThatFindsNothingSaysSo() async {
        let model = makeModel()
        await model.start()
        await model.restore()
        #expect(model.message == .nothingToRestore)
        #expect(!model.state.grantsAccess)
        model.stop()
    }

    @Test func aChangeMadeElsewhereReachesTheScreen() async throws {
        let model = makeModel()
        await model.start()
        service.setState(.subscribed(renews: later, willRenew: true))
        for _ in 0..<50 where model.state == .notSubscribed { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.state == .subscribed(renews: later, willRenew: true))
        model.stop()
    }

    // MARK: The trial countdown and the summary (E13-S5)

    private func model(
        state: SubscriptionState, summary: FakeEntitlementSummaryStore? = nil, seen: FakePaywallSeen? = nil,
        now: Date
    ) -> SubscriptionModel {
        SubscriptionModel(
            service: FakeSubscriptionService(state: state), seen: seen ?? FakePaywallSeen(true), summary: summary,
            now: { now })
    }

    @Test func theTrialCountdownCountsWholeDaysLeftRoundedUp() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let threeDays = model(state: .trialing(until: now.addingTimeInterval(3 * 86_400 - 60)), now: now)
        await threeDays.start()
        #expect(threeDays.trialDaysLeft == 3)
        #expect(SubscriptionWording.trialCountdown(daysLeft: 3).contains("3 days"))
        #expect(SubscriptionWording.trialCountdown(daysLeft: 1).localizedCaseInsensitiveContains("one day"))
        let none = model(state: .subscribed(renews: later, willRenew: true), now: now)
        await none.start()
        #expect(none.trialDaysLeft == nil)
        threeDays.stop()
        none.stop()
    }

    @Test func theTrialEndingNoticeShowsOnceAtADayLeftAndNeverForAPaidPlan() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let seen = FakePaywallSeen(true)
        let soon = model(state: .trialing(until: now.addingTimeInterval(20 * 3_600)), seen: seen, now: now)
        await soon.start()
        #expect(soon.showsTrialEndingNotice)
        soon.dismissTrialEndingNotice()
        #expect(!soon.showsTrialEndingNotice)
        #expect(seen.hasSeenTrialEndingNotice, "it is not shown again later")

        let again = model(state: .trialing(until: now.addingTimeInterval(20 * 3_600)), seen: seen, now: now)
        await again.start()
        #expect(!again.showsTrialEndingNotice)

        let early = model(state: .trialing(until: now.addingTimeInterval(5 * 86_400)), now: now)
        await early.start()
        #expect(!early.showsTrialEndingNotice, "five days left is too early to nag")
        let paid = model(state: .subscribed(renews: now.addingTimeInterval(3_600), willRenew: true), now: now)
        await paid.start()
        #expect(!paid.showsTrialEndingNotice)
        for item in [soon, again, early, paid] { item.stop() }
    }

    @Test func theSummaryFollowsTheStateAndIsRemovedOnDeleteAll() async {
        let store = FakeEntitlementSummaryStore()
        let end = Date(timeIntervalSince1970: 1_900_000_000)
        let model = model(state: .trialing(until: end), summary: store, now: Date(timeIntervalSince1970: 1_800_000_000))
        await model.start()
        #expect(store.read() == EntitlementSummary(status: .trial, endsAt: end))
        model.eraseSummary()
        #expect(store.read() == nil)
        model.stop()
    }

    @Test func manageSubscriptionsAsksTheService() async {
        let model = makeModel()
        await model.manage()
        #expect(service.manageCalls == 1)
    }

    @Test func aMissingProductCanBeLoadedAgain() async {
        service.setProduct(nil)
        let model = makeModel()
        await model.start()
        #expect(model.product == nil)
        service.setProduct(FakeSubscriptionService.sampleProduct)
        await model.reloadProduct()
        #expect(model.product == FakeSubscriptionService.sampleProduct)
        model.stop()
    }
}

/// E13-S4: the price and the trial are only ever what the product says.
struct SubscriptionWordingTests {
    private func product(price: String, trial: SubscriptionLength?) -> SubscriptionProduct {
        SubscriptionProduct(
            id: "p", displayName: "P", displayPrice: price, period: SubscriptionLength(value: 1, unit: .month),
            freeTrial: trial)
    }

    @Test func theTrialAndPriceLineFollowTheProduct() {
        let line = SubscriptionWording.priceLine(
            product(price: "₹149.00", trial: SubscriptionLength(value: 1, unit: .week)))
        #expect(line.contains("₹149.00"))
        #expect(line.contains("1 week"))
        let changed = SubscriptionWording.priceLine(
            product(price: "$2.99", trial: SubscriptionLength(value: 3, unit: .day)))
        #expect(changed.contains("$2.99"))
        #expect(changed.contains("3 days"))
        #expect(!changed.contains("1 week"), "changing the product changes the paywall")
    }

    @Test func withoutATrialThereIsNoTrialWording() {
        let value = product(price: "$1.99", trial: nil)
        #expect(SubscriptionWording.priceLine(value).contains("$1.99"))
        #expect(!SubscriptionWording.priceLine(value).localizedCaseInsensitiveContains("free"))
        #expect(!SubscriptionWording.buttonTitle(value).localizedCaseInsensitiveContains("trial"))
        #expect(SubscriptionWording.buttonTitle(value).contains("$1.99"))
    }

    @Test func theButtonSaysWhatHappens() {
        let trial = product(price: "$1.99", trial: SubscriptionLength(value: 1, unit: .week))
        #expect(SubscriptionWording.buttonTitle(trial).contains("Free Trial"))
        #expect(SubscriptionWording.renewalText(trial).contains("cancel"))
    }

    /// The price and the length of the trial must come from StoreKit, never from the app's words.
    @Test func noPriceOrTrialLengthIsWrittenInTheViewsOrWording() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/UI")
        for name in ["SubscriptionWording.swift", "Mobile/PaywallView.swift", "SubscriptionModel.swift"] {
            // Comments may give examples; only the code and its strings count.
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for forbidden in ["1.99", "7 days", "7-day", "$1", "199"] {
                #expect(!text.contains(forbidden), "\(name) contains \(forbidden)")
            }
        }
    }
}
