import Domain
import Foundation
import Synchronization

/// A subscription that needs no App Store: its state, product, and answers are set by the test.
public final class FakeSubscriptionService: SubscriptionProviding, SubscriptionProofProviding {
    public static let sampleProduct = SubscriptionProduct(
        id: "test.pro.monthly", displayName: "Test Pro", displayPrice: "$9.99",
        period: SubscriptionLength(value: 1, unit: .month), freeTrial: SubscriptionLength(value: 1, unit: .week))

    private struct State {
        var state: SubscriptionState
        var product: SubscriptionProduct?
        var purchaseOutcome: PurchaseOutcome = .purchased
        var purchaseState: SubscriptionState?
        var restoreFindsSubscription = false
        var starts = 0
        var purchases = 0
        var restores = 0
        var manageCalls = 0
        var reachable = true
        var reachabilityChecks = 0
        var observers: [UUID: AsyncStream<SubscriptionState>.Continuation] = [:]
    }

    private let box: Mutex<State>

    public init(state: SubscriptionState = .notSubscribed, product: SubscriptionProduct? = sampleProduct) {
        box = Mutex(State(state: state, product: product))
    }

    public var starts: Int { box.withLock { $0.starts } }
    public var purchases: Int { box.withLock { $0.purchases } }
    public var restores: Int { box.withLock { $0.restores } }
    public var manageCalls: Int { box.withLock { $0.manageCalls } }

    /// What the next `purchase()` answers, and the state it leaves behind when it works.
    public func willPurchase(_ outcome: PurchaseOutcome, leaving state: SubscriptionState? = nil) {
        box.withLock {
            $0.purchaseOutcome = outcome
            $0.purchaseState = state
        }
    }

    public func setRestoreFindsSubscription(_ found: Bool, leaving state: SubscriptionState? = nil) {
        box.withLock {
            $0.restoreFindsSubscription = found
            $0.purchaseState = state ?? $0.purchaseState
        }
    }

    public func setProduct(_ product: SubscriptionProduct?) { box.withLock { $0.product = product } }
    public func setReachable(_ reachable: Bool) { box.withLock { $0.reachable = reachable } }

    /// Changes the state and tells everyone listening.
    public func setState(_ state: SubscriptionState) {
        let observers = box.withLock { box -> [AsyncStream<SubscriptionState>.Continuation] in
            box.state = state
            return Array(box.observers.values)
        }
        for observer in observers { observer.yield(state) }
    }

    // MARK: SubscriptionProviding

    public func start() async { box.withLock { $0.starts += 1 } }
    public func product() async -> SubscriptionProduct? { box.withLock { $0.product } }
    public func currentState() async -> SubscriptionState { box.withLock { $0.state } }

    public var stateUpdates: AsyncStream<SubscriptionState> {
        AsyncStream { continuation in
            let id = UUID()
            // Like the real service, a new listener is told the current state first, so it cannot miss a
            // change that happened just before it started listening.
            let current = box.withLock { box -> SubscriptionState in
                box.observers[id] = continuation
                return box.state
            }
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in self?.box.withLock { $0.observers[id] = nil } }
        }
    }

    public func purchase() async -> PurchaseOutcome {
        let (outcome, leaving) = box.withLock { box -> (PurchaseOutcome, SubscriptionState?) in
            box.purchases += 1
            return (box.purchaseOutcome, box.purchaseState)
        }
        if outcome == .purchased, let leaving { setState(leaving) }
        return outcome
    }

    public func restore() async -> Bool {
        let (found, leaving) = box.withLock { box -> (Bool, SubscriptionState?) in
            box.restores += 1
            return (box.restoreFindsSubscription, box.purchaseState)
        }
        if found, let leaving { setState(leaving) }
        return found
    }

    public func showManageSubscriptions() async { box.withLock { $0.manageCalls += 1 } }
    public var reachabilityChecks: Int { box.withLock { $0.reachabilityChecks } }
    public func canReachAppStore() async -> Bool {
        box.withLock {
            $0.reachabilityChecks += 1
            return $0.reachable
        }
    }

    // MARK: SubscriptionProofProviding

    public func signedTransaction() async -> String? {
        box.withLock { $0.state.grantsAccess ? "signed-transaction" : nil }
    }
}
