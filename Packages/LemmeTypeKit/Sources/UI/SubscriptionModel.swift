import Domain
import Foundation
import Observation

/// The subscription as the screens see it: the state, the product with its price and trial, and what happened
/// on the last try (E13-S4, ADR 0034). It never shows a price or length it did not get from the service.
@MainActor
@Observable
public final class SubscriptionModel {
    /// What the person is told about the last purchase or restore. The words are the views'.
    public enum Message: Equatable, Sendable {
        case cancelled
        case pending
        case unverified
        case failed
        case nothingToRestore
    }

    public private(set) var state: SubscriptionState = .unknown
    public private(set) var product: SubscriptionProduct?
    public private(set) var isWorking = false
    public private(set) var message: Message?
    /// The paywall is on screen. Settings, and a refused dictation, set this too.
    public var isShowingPaywall = false
    /// The trial-ending notice was closed (it is shown once; see ``showsTrialEndingNotice``).
    public private(set) var trialNoticeDismissed = false

    private let service: any SubscriptionProviding
    private let seen: any PaywallSeenStoring
    private let summary: (any EntitlementSummaryStoring)?
    private let now: @Sendable () -> Date
    private var startTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?

    public init(
        service: any SubscriptionProviding, seen: any PaywallSeenStoring,
        summary: (any EntitlementSummaryStoring)? = nil, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.seen = seen
        self.summary = summary
        self.now = now
    }

    /// Whole days left in the free trial, rounded up, or `nil` when not in a trial.
    public var trialDaysLeft: Int? {
        guard case .trialing(let until) = state, until > now() else { return nil }
        return Int((until.timeIntervalSince(now()) / 86_400).rounded(.up))
    }

    /// One notice, in the app, when a day or less is left in the trial. It is not a push notification.
    public var showsTrialEndingNotice: Bool {
        guard let days = trialDaysLeft, days <= 1 else { return false }
        return !trialNoticeDismissed && !seen.hasSeenTrialEndingNotice
    }

    public func dismissTrialEndingNotice() {
        trialNoticeDismissed = true
        seen.hasSeenTrialEndingNotice = true
    }

    /// Removes the summary the keyboard and intents read (Delete All Local Data).
    public func eraseSummary() {
        summary?.clear()
    }

    private func publishSummary() {
        summary?.write(EntitlementSummary(state))
    }

    /// Starts loading in the background, so launching never waits for the App Store.
    public func begin() {
        guard startTask == nil else { return }
        startTask = Task { await start() }
    }

    public func start() async {
        await service.start()
        state = await service.currentState()
        publishSummary()
        product = await service.product()
        if updatesTask == nil {
            updatesTask = Task { [service] in
                for await update in service.stateUpdates {
                    self.state = update
                    self.publishSummary()
                }
            }
        }
        offerThePaywallOnce()
    }

    public func stop() {
        startTask?.cancel()
        updatesTask?.cancel()
        startTask = nil
        updatesTask = nil
    }

    /// Shown once on its own, to someone who has no subscription and has not seen it yet. It can be closed.
    private func offerThePaywallOnce() {
        guard !seen.hasSeenPaywall, state == .notSubscribed || state.isLapsed else { return }
        seen.hasSeenPaywall = true
        isShowingPaywall = true
    }

    public func showPaywall() {
        message = nil
        isShowingPaywall = true
    }

    public func reloadProduct() async {
        isWorking = true
        product = await service.product()
        isWorking = false
    }

    public func purchase() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        switch await service.purchase() {
        case .purchased:
            state = await service.currentState()
            publishSummary()
            isShowingPaywall = false
        case .pending: message = .pending
        case .cancelled: message = .cancelled
        case .unverified: message = .unverified
        case .failed: message = .failed
        }
        isWorking = false
    }

    public func restore() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        if await service.restore() {
            state = await service.currentState()
            publishSummary()
            isShowingPaywall = false
        } else {
            message = .nothingToRestore
        }
        isWorking = false
    }

    public func manage() async {
        await service.showManageSubscriptions()
    }
}

extension SubscriptionState {
    /// Had a subscription once and has none now.
    var isLapsed: Bool {
        switch self {
        case .expired, .revoked, .billingRetry: true
        case .unknown, .notSubscribed, .trialing, .subscribed, .gracePeriod: false
        }
    }
}
