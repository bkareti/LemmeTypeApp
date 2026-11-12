import Domain
import Foundation
import StoreKit
import StoreKitTest
import Subscriptions
import Testing

/// E13-S4: the real StoreKit service against Apple's local test session and the repository's
/// `LemmeType.storekit` (the same product, price, and offer as App Store Connect). Serial, because StoreKit's
/// test session is shared by the whole process.
@Suite(.serialized)
struct StoreKitSubscriptionServiceTests {
    static let productID = "com.lemmetype.LemmeType.iOS.pro.monthly"

    /// The suite is serial, so one session is kept alive at a time. A session that is released ends StoreKit's
    /// test environment, and StoreKit then finds no products.
    private nonisolated(unsafe) static var keptSession: SKTestSession?

    /// A fresh test session with no purchases, no simulated errors, and no dialogs to click. The earlier session
    /// is released first: StoreKit's test environment carries simulated errors and trial history from one
    /// session to the next unless each test starts clean.
    private func makeSession() async throws -> SKTestSession {
        Self.keptSession = nil
        let session = try SKTestSession(configurationFileNamed: "LemmeType")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.billingGracePeriodIsEnabled = false
        session.shouldEnterBillingRetryOnRenewal = false
        try await session.setSimulatedError(nil, forAPI: .purchase)
        try await session.setSimulatedError(nil, forAPI: .verification)
        Self.keptSession = session
        try? await Task.sleep(for: .milliseconds(300))
        return session
    }

    private func makeService() async -> StoreKitSubscriptionService {
        let service = StoreKitSubscriptionService(productID: Self.productID)
        await service.start()
        return service
    }

    /// Waits for StoreKit's updates to reach the service.
    private func wait(
        _ service: StoreKitSubscriptionService, until matches: (SubscriptionState) -> Bool
    ) async -> SubscriptionState {
        var state = await service.currentState()
        for _ in 0..<100 where !matches(state) {
            try? await Task.sleep(for: .milliseconds(100))
            state = await service.currentState()
        }
        return state
    }

    private func isTrialing(_ state: SubscriptionState) -> Bool {
        if case .trialing = state { return true }
        return false
    }

    private func isSubscribed(_ state: SubscriptionState) -> Bool {
        if case .subscribed = state { return true }
        return false
    }

    // MARK: Product

    @Test func theProductComesFromStoreKitWithItsPriceAndTrial() async throws {
        _ = try await makeSession()
        let product = try #require(await makeService().product())
        #expect(product.id == Self.productID)
        #expect(product.displayPrice == "$1.99", "read from LemmeType.storekit, not written in the app")
        #expect(product.period == SubscriptionLength(value: 1, unit: .month))
        #expect(product.freeTrial == SubscriptionLength(value: 1, unit: .week))
    }

    // MARK: Purchase, trial, and what follows

    @Test func aPurchaseStartsTheFreeTrialSevenDaysOut() async throws {
        _ = try await makeSession()
        let service = await makeService()
        #expect(await service.currentState() == .notSubscribed)
        #expect(await service.purchase() == .purchased)
        guard case .trialing(let until) = await service.currentState() else {
            Issue.record("expected a trial, got \(await service.currentState())")
            return
        }
        let days = until.timeIntervalSinceNow / 86_400
        #expect(days > 6.9 && days < 7.1, "the trial ends about 7 days from now")
        #expect(await service.currentState().grantsAccess)
    }

    @Test func theTrialMovesToSubscribedWhenItRenews() async throws {
        let session = try await makeSession()
        let service = await makeService()
        _ = await service.purchase()
        try session.forceRenewalOfSubscription(productIdentifier: Self.productID)
        let state = await wait(service) { isSubscribed($0) }
        #expect(isSubscribed(state), "got \(state)")
    }

    @Test func cancellingKeepsAccessUntilTheEnd() async throws {
        let session = try await makeSession()
        let service = await makeService()
        _ = await service.purchase()
        try session.forceRenewalOfSubscription(productIdentifier: Self.productID)
        _ = await wait(service) { isSubscribed($0) }
        let latest = try #require(session.allTransactions().last)
        try session.disableAutoRenewForTransaction(identifier: latest.identifier)
        let state = await wait(service) {
            if case .subscribed(_, let willRenew) = $0 { return !willRenew }
            return false
        }
        guard case .subscribed(_, let willRenew) = state else {
            Issue.record("expected subscribed, got \(state)")
            return
        }
        #expect(!willRenew, "renewal is off")
        #expect(state.grantsAccess, "but access continues until the period ends")
    }

    @Test func expiryEndsAccess() async throws {
        let session = try await makeSession()
        let service = await makeService()
        _ = await service.purchase()
        try session.expireSubscription(productIdentifier: Self.productID)
        let state = await wait(service) { !$0.grantsAccess }
        guard case .expired = state else {
            Issue.record("expected expired, got \(state)")
            return
        }
        #expect(await service.signedTransaction() == nil, "nothing for the gateway once it has ended")
    }

    @Test func aRefundRevokesIt() async throws {
        let session = try await makeSession()
        let service = await makeService()
        _ = await service.purchase()
        let transaction = try #require(session.allTransactions().last)
        try session.refundTransaction(identifier: transaction.identifier)
        let state = await wait(service) { $0 == .revoked }
        #expect(state == .revoked, "got \(state)")
        #expect(await service.signedTransaction() == nil)
    }

    @Test func aFailedRenewalWithoutGraceIsBillingRetry() async throws {
        let session = try await makeSession()
        session.billingGracePeriodIsEnabled = false
        session.shouldEnterBillingRetryOnRenewal = true
        let service = await makeService()
        _ = await service.purchase()
        try session.forceRenewalOfSubscription(productIdentifier: Self.productID)
        let state = await wait(service) { $0 == .billingRetry }
        #expect(state == .billingRetry, "got \(state)")
        #expect(!state.grantsAccess)
    }

    @Test func aFailedRenewalWithGraceKeepsAccessForAWhile() async throws {
        let session = try await makeSession()
        session.billingGracePeriodIsEnabled = true
        session.shouldEnterBillingRetryOnRenewal = true
        let service = await makeService()
        _ = await service.purchase()
        try session.forceRenewalOfSubscription(productIdentifier: Self.productID)
        let state = await wait(service) {
            if case .gracePeriod = $0 { return true }
            return false
        }
        guard case .gracePeriod = state else {
            Issue.record("expected a grace period, got \(state)")
            return
        }
        #expect(state.grantsAccess)
        #expect(await service.signedTransaction() != nil, "the gateway can still be shown the latest transaction")
    }

    @Test func theTrialIsGoneOnceItHasBeenUsed() async throws {
        let session = try await makeSession()
        let service = await makeService()
        let first = try #require(await service.product())
        #expect(first.freeTrial != nil)
        _ = await service.purchase()
        try session.expireSubscription(productIdentifier: Self.productID)
        _ = await wait(service) { !$0.grantsAccess }
        let second = try #require(await service.product())
        #expect(second.freeTrial == nil, "this Apple ID has used its free week")
        #expect(second.displayPrice == "$1.99")
    }

    // MARK: Attempts that do not end in a subscription

    @Test func aCancelledPurchaseLeavesNothingUnlocked() async throws {
        let session = try await makeSession()
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        let service = await makeService()
        let outcome = await service.purchase()
        #expect(outcome == .cancelled, "got \(outcome)")
        #expect(await service.currentState() == .notSubscribed)
    }

    @Test func aPurchaseWaitingForApprovalIsPending() async throws {
        let session = try await makeSession()
        session.askToBuyEnabled = true
        let service = await makeService()
        #expect(await service.purchase() == .pending)
        #expect(await service.currentState() == .notSubscribed)
    }

    @Test func aTransactionThatCannotBeVerifiedGrantsNothing() async throws {
        let session = try await makeSession()
        try await session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
        let service = await makeService()
        let outcome = await service.purchase()
        #expect(outcome == .unverified, "got \(outcome)")
        #expect(await service.currentState() == .notSubscribed)
        #expect(await service.signedTransaction() == nil)
    }

    @Test func aPurchaseThatFailsReportsFailure() async throws {
        let session = try await makeSession()
        try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        let service = await makeService()
        #expect(await service.purchase() == .failed)
        #expect(await service.currentState() == .notSubscribed)
    }

    // MARK: Restore, the gateway's proof, and listening

    @Test func restoreFindsAnExistingSubscriptionOnAFreshInstall() async throws {
        _ = try await makeSession()
        let original = await makeService()
        #expect(await original.purchase() == .purchased)

        let freshInstall = StoreKitSubscriptionService(productID: Self.productID)
        #expect(await freshInstall.restore(), "restore finds the subscription for this Apple Account")
        #expect(await freshInstall.currentState().grantsAccess)
    }

    @Test func restoreWithNothingToRestoreFindsNothing() async throws {
        _ = try await makeSession()
        let service = StoreKitSubscriptionService(productID: Self.productID)
        #expect(await service.restore() == false)
        #expect(await service.currentState() == .notSubscribed)
    }

    @Test func theGatewayGetsAVerifiedSignedTransactionOnlyWhileSubscribed() async throws {
        _ = try await makeSession()
        let service = await makeService()
        #expect(await service.signedTransaction() == nil, "nothing before a purchase")
        _ = await service.purchase()
        let signed = try #require(await service.signedTransaction())
        #expect(signed.split(separator: ".").count == 3, "a JWS: header, payload, signature")
        #expect(!signed.contains(" "))
    }

    @Test func stateChangesAreAnnouncedToListeners() async throws {
        _ = try await makeSession()
        let service = await makeService()
        let listener = Task { () -> [SubscriptionState] in
            var seen: [SubscriptionState] = []
            for await state in service.stateUpdates {
                seen.append(state)
                if state.grantsAccess { break }
            }
            return seen
        }
        _ = await service.purchase()
        let seen = await listener.value
        #expect(seen.first == .notSubscribed, "a new listener first hears the current state")
        #expect(seen.last?.grantsAccess == true)
    }
}
