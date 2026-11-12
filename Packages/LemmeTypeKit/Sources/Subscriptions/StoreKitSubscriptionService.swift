import Domain
import Foundation
import StoreKit

#if os(iOS)
    import UIKit
#endif

/// The monthly subscription through StoreKit 2 (ADR 0034). The one place that imports StoreKit.
///
/// Only a transaction StoreKit has verified counts: an unverified one is reported and ignored. State is
/// worked out from StoreKit's own records, which StoreKit keeps on the device, so it works offline.
public actor StoreKitSubscriptionService: SubscriptionProviding, SubscriptionProofProviding {
    private let productID: String
    private var loadedProduct: Product?
    private var state: SubscriptionState = .unknown
    private var observers: [UUID: AsyncStream<SubscriptionState>.Continuation] = [:]
    private var updatesTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    public init(productID: String) {
        self.productID = productID
    }

    deinit {
        updatesTask?.cancel()
        statusTask?.cancel()
    }

    // MARK: SubscriptionProviding

    public func start() async {
        if updatesTask == nil {
            // Purchases made elsewhere (Family, another device, Ask to Buy approved later) arrive here.
            updatesTask = Task { [weak self] in
                for await update in Transaction.updates {
                    await self?.handle(update)
                }
            }
            statusTask = Task { [weak self] in
                for await _ in Product.SubscriptionInfo.Status.updates {
                    await self?.refresh()
                }
            }
        }
        await refresh()
    }

    public func product() async -> SubscriptionProduct? {
        guard let product = await loadProduct(), let info = product.subscription else { return nil }
        var trial: SubscriptionLength?
        if await info.isEligibleForIntroOffer, let offer = info.introductoryOffer, offer.paymentMode == .freeTrial {
            trial = Self.period(offer.period, times: offer.periodCount)
        }
        return SubscriptionProduct(
            id: product.id, displayName: product.displayName, displayPrice: product.displayPrice,
            period: Self.period(info.subscriptionPeriod, times: 1), freeTrial: trial)
    }

    /// Always worked out again, from StoreKit's own records on the device: an expiry by the clock sends no
    /// update, and asking is cheap and works offline.
    public func currentState() async -> SubscriptionState {
        await refresh()
        return state
    }

    public nonisolated var stateUpdates: AsyncStream<SubscriptionState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.add(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.remove(id) }
            }
        }
    }

    public func purchase() async -> PurchaseOutcome {
        guard let product = await loadProduct() else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refresh()
                    return .purchased
                case .unverified:
                    await refresh()
                    return .unverified
                }
            case .pending: return .pending
            case .userCancelled: return .cancelled
            @unknown default: return .failed
            }
        } catch {
            // A closed purchase sheet can arrive as a thrown error as well as a result, in either of
            // StoreKit's two error types.
            if let storeKit = error as? StoreKitError, case .userCancelled = storeKit { return .cancelled }
            let nsError = error as NSError
            if nsError.domain == SKErrorDomain, nsError.code == SKError.paymentCancelled.rawValue { return .cancelled }
            return .failed
        }
    }

    public func restore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            return false
        }
        await refresh()
        return state.grantsAccess
    }

    public func showManageSubscriptions() async {
        #if os(iOS)
            let scene = await MainActor.run {
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }
            }
            if let scene { try? await AppStore.showManageSubscriptions(in: scene) }
        #endif
    }

    // MARK: SubscriptionProofProviding

    /// The signed transaction for the gateway (E13-S3), from a verified entitlement or, in a grace period,
    /// the latest verified transaction. `nil` when there is nothing the gateway could accept.
    public func signedTransaction() async -> String? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == productID,
                transaction.revocationDate == nil
            {
                return result.jwsRepresentation
            }
        }
        // Only in a grace period: an expired or refunded subscription has nothing the gateway should accept.
        guard case .gracePeriod = await currentState(),
            let latest = await Transaction.latest(for: productID), case .verified(let transaction) = latest,
            transaction.revocationDate == nil
        else { return nil }
        return latest.jwsRepresentation
    }

    // MARK: State

    private func handle(_ update: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = update { await transaction.finish() }
        await refresh()
    }

    private func refresh() async {
        publish(await computeState())
    }

    private func computeState() async -> SubscriptionState {
        guard let product = await loadProduct(), let info = product.subscription,
            let statuses = try? await info.status
        else { return await entitlementOnlyState() }
        let snapshots = statuses.compactMap(Self.snapshot(from:))
        return SubscriptionSnapshot.state(of: snapshots)
    }

    /// Used when the product cannot be loaded (for example the first launch is offline): StoreKit's records of
    /// verified entitlements still say whether the person is subscribed.
    private func entitlementOnlyState() async -> SubscriptionState {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productID == productID,
                transaction.revocationDate == nil, let expiration = transaction.expirationDate, expiration > Date()
            else { continue }
            let isTrial = transaction.offer?.type == .introductory && transaction.offer?.paymentMode == .freeTrial
            return isTrial ? .trialing(until: expiration) : .subscribed(renews: expiration, willRenew: true)
        }
        return .notSubscribed
    }

    private func publish(_ new: SubscriptionState) {
        guard new != state else { return }
        state = new
        for continuation in observers.values { continuation.yield(new) }
    }

    private func add(_ continuation: AsyncStream<SubscriptionState>.Continuation, id: UUID) {
        observers[id] = continuation
        continuation.yield(state)
    }

    private func remove(_ id: UUID) {
        observers[id] = nil
    }

    private func loadProduct() async -> Product? {
        if let loadedProduct { return loadedProduct }
        loadedProduct = try? await Product.products(for: [productID]).first
        return loadedProduct
    }

    // MARK: Mapping

    private static func snapshot(from status: Product.SubscriptionInfo.Status) -> SubscriptionSnapshot? {
        // Anything StoreKit could not verify grants nothing.
        guard case .verified(let transaction) = status.transaction else { return nil }
        let kind: SubscriptionSnapshot.Kind?
        switch status.state {
        case .subscribed: kind = .subscribed
        case .inGracePeriod: kind = .inGracePeriod
        case .inBillingRetryPeriod: kind = .inBillingRetry
        case .expired: kind = .expired
        case .revoked: kind = .revoked
        default: kind = nil
        }
        guard let kind else { return nil }
        var willRenew = false
        var graceUntil: Date?
        if case .verified(let renewal) = status.renewalInfo {
            willRenew = renewal.willAutoRenew
            graceUntil = renewal.gracePeriodExpirationDate
        }
        return SubscriptionSnapshot(
            kind: kind, expiration: transaction.expirationDate,
            isFreeTrial: transaction.offer?.type == .introductory && transaction.offer?.paymentMode == .freeTrial,
            willRenew: willRenew, graceUntil: graceUntil, purchased: transaction.purchaseDate)
    }

    private static func period(_ period: Product.SubscriptionPeriod, times: Int) -> SubscriptionLength {
        let unit: SubscriptionLength.Unit =
            switch period.unit {
            case .day: .day
            case .week: .week
            case .month: .month
            case .year: .year
            @unknown default: .month
            }
        return SubscriptionLength(value: period.value * max(1, times), unit: unit)
    }
}
