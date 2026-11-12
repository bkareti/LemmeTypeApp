import Domain
import Foundation

/// Words for what StoreKit reports. The numbers and the price come from StoreKit; only the unit names and the
/// sentences around them are written here (E13-S4).
extension SubscriptionLength {
    /// "1 week", "7 days": the length as the system words it.
    var localizedDuration: String {
        var components = DateComponents()
        switch unit {
        case .day: components.day = value
        case .week: components.weekOfMonth = value
        case .month: components.month = value
        case .year: components.year = value
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        formatter.maximumUnitCount = 1
        return formatter.string(from: components) ?? "\(value)"
    }

    /// "month", for "$1.99 per month". Only meaningful for a single unit, which is what a plan reports.
    var unitName: String {
        switch unit {
        case .day: String(localized: "day", bundle: .module, comment: "One day, as in 'price per day'")
        case .week: String(localized: "week", bundle: .module, comment: "One week, as in 'price per week'")
        case .month: String(localized: "month", bundle: .module, comment: "One month, as in 'price per month'")
        case .year: String(localized: "year", bundle: .module, comment: "One year, as in 'price per year'")
        }
    }
}

enum SubscriptionWording {
    /// "7 days free, then $1.99 per month" when there is a trial, "$1.99 per month" when there is not.
    static func priceLine(_ product: SubscriptionProduct) -> String {
        if let trial = product.freeTrial {
            return String(
                localized:
                    "\(trial.localizedDuration) free, then \(product.displayPrice) per \(product.period.unitName)",
                bundle: .module, comment: "The price line of the subscription: a free trial, then the price")
        }
        return String(
            localized: "\(product.displayPrice) per \(product.period.unitName)", bundle: .module,
            comment: "The price line of the subscription when there is no free trial")
    }

    /// The button: what happens when it is tapped.
    static func buttonTitle(_ product: SubscriptionProduct) -> String {
        if let trial = product.freeTrial {
            return String(
                localized: "Start \(trial.localizedDuration) Free Trial", bundle: .module,
                comment: "Button that starts the free trial of the subscription")
        }
        return String(
            localized: "Subscribe for \(product.displayPrice) per \(product.period.unitName)", bundle: .module,
            comment: "Button that starts the paid subscription, naming its price")
    }

    static func renewalText(_ product: SubscriptionProduct) -> String {
        String(
            localized:
                "Renews automatically each \(product.period.unitName) until you cancel. Cancel any time in Settings › Apple Account › Subscriptions. Payment is charged to your Apple Account.",
            bundle: .module,
            comment: "The renewal and cancellation terms shown with the subscription price")
    }

    static func message(_ message: SubscriptionModel.Message) -> String {
        switch message {
        case .cancelled:
            String(
                localized: "The purchase was cancelled. You have not been charged.", bundle: .module,
                comment: "Shown after the person closed the purchase sheet")
        case .pending:
            String(
                localized: "The purchase is waiting for approval. It will start when it is approved.",
                bundle: .module, comment: "Shown when a purchase needs approval, for example Ask to Buy")
        case .unverified:
            String(
                localized: "The App Store’s answer could not be checked, so nothing was unlocked. Try again.",
                bundle: .module, comment: "Shown when a purchase could not be verified")
        case .failed:
            String(
                localized: "The purchase didn’t go through. Check your connection and try again.", bundle: .module,
                comment: "Shown when a purchase fails")
        case .nothingToRestore:
            String(
                localized: "No active subscription was found for this Apple Account.", bundle: .module,
                comment: "Shown after restoring purchases found nothing")
        }
    }

    /// One sentence for the state, with dates in the person's own format.
    static func statusLine(_ state: SubscriptionState) -> String {
        switch state {
        case .unknown, .notSubscribed:
            String(
                localized: "Not subscribed.", bundle: .module, comment: "Subscription status when there is none")
        case .trialing(let until):
            String(
                localized: "Free trial. It ends \(until.formatted(date: .abbreviated, time: .omitted)).",
                bundle: .module, comment: "Subscription status during the free trial")
        case .subscribed(let renews, let willRenew):
            if let renews, willRenew {
                String(
                    localized: "Subscribed. Renews \(renews.formatted(date: .abbreviated, time: .omitted)).",
                    bundle: .module, comment: "Subscription status when it renews on a date")
            } else if let renews {
                String(
                    localized:
                        "Subscribed. Ends \(renews.formatted(date: .abbreviated, time: .omitted)); it will not renew.",
                    bundle: .module, comment: "Subscription status when renewal is turned off")
            } else {
                String(localized: "Subscribed.", bundle: .module, comment: "Subscription status when active")
            }
        case .gracePeriod(let until):
            String(
                localized:
                    "Payment problem. Access continues until \(until.formatted(date: .abbreviated, time: .omitted)). Update your payment method.",
                bundle: .module, comment: "Subscription status during the payment grace period")
        case .billingRetry:
            String(
                localized: "Payment problem. Update your payment method to continue.", bundle: .module,
                comment: "Subscription status while Apple retries a failed payment")
        case .expired(let ended):
            String(
                localized: "The subscription ended \(ended.formatted(date: .abbreviated, time: .omitted)).",
                bundle: .module, comment: "Subscription status after it expired")
        case .revoked:
            String(
                localized: "The subscription was refunded.", bundle: .module,
                comment: "Subscription status after a refund")
        }
    }
}
