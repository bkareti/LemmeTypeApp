#if os(iOS)
    import Domain
    import SwiftUI

    /// The subscription offer (E13-S4, ADR 0034). Everything about the price and the trial comes from the
    /// model's product. It always has a way to close it, and links the terms and the privacy policy that
    /// App Review requires beside the price (Guideline 3.1.2).
    public struct PaywallView: View {
        @Bindable var model: SubscriptionModel

        public init(model: SubscriptionModel) {
            self.model = model
        }

        public var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        Image(systemName: "mic.fill").font(.largeTitle).foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(String(localized: "LemmeType", bundle: .module, comment: "The app's name in the paywall"))
                            .font(.title.bold())
                        benefits
                        offer
                        if let message = model.message {
                            Text(SubscriptionWording.message(message)).font(.footnote).foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("paywall.message")
                        }
                        Button(String(localized: "Restore Purchases", bundle: .module)) {
                            Task { await model.restore() }
                        }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("paywall.restore")
                        links
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Close", bundle: .module)) { model.isShowingPaywall = false }
                            .accessibilityIdentifier("paywall.close")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .task { if model.product == nil { await model.reloadProduct() } }
        }

        private var benefits: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    String(
                        localized: "Dictate on your iPhone, with your voice kept on the device.", bundle: .module,
                        comment: "A benefit listed in the paywall"), systemImage: "lock.shield")
                Label(
                    String(
                        localized: "Cloud speech for Telugu and more, with nothing to set up.", bundle: .module,
                        comment: "A benefit listed in the paywall"), systemImage: "cloud")
            }
            .font(.subheadline)
        }

        @ViewBuilder private var offer: some View {
            if let product = model.product {
                VStack(spacing: 8) {
                    Text(SubscriptionWording.priceLine(product)).font(.headline).multilineTextAlignment(.center)
                        .accessibilityIdentifier("paywall.price")
                    Button {
                        Task { await model.purchase() }
                    } label: {
                        Text(SubscriptionWording.buttonTitle(product)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("paywall.start")
                    Text(SubscriptionWording.renewalText(product)).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("paywall.renewal")
                }
            } else if model.isWorking {
                ProgressView().accessibilityIdentifier("paywall.loading")
            } else {
                VStack(spacing: 8) {
                    Text(
                        String(
                            localized: "The subscription couldn’t be loaded. Check your connection.", bundle: .module,
                            comment: "Shown in the paywall when the App Store gives no product")
                    )
                    .font(.footnote)
                    Button(String(localized: "Try Again", bundle: .module)) { Task { await model.reloadProduct() } }
                        .accessibilityIdentifier("paywall.retry")
                }
            }
        }

        private var links: some View {
            HStack(spacing: 20) {
                Link(String(localized: "Terms of Use", bundle: .module), destination: PublicLinks.termsOfUse)
                    .accessibilityIdentifier("paywall.terms")
                Link(String(localized: "Privacy Policy", bundle: .module), destination: PublicLinks.privacyPolicy)
                    .accessibilityIdentifier("paywall.privacy")
            }
            .font(.footnote)
        }
    }

    /// The Subscription section of Settings on iPhone and iPad (E13-S4).
    struct MobileSubscriptionSection: View {
        let model: SubscriptionModel

        var body: some View {
            Section {
                Text(SubscriptionWording.statusLine(model.state))
                    .accessibilityIdentifier("settings.subscription.status")
                if let days = model.trialDaysLeft {
                    Text(SubscriptionWording.trialCountdown(daysLeft: days)).font(.footnote)
                        .accessibilityIdentifier("settings.subscription.countdown")
                }
                if !model.state.grantsAccess {
                    Button(startTitle) { model.showPaywall() }
                        .accessibilityIdentifier("settings.subscription.start")
                }
                Button(String(localized: "Manage Subscription", bundle: .module)) {
                    Task { await model.manage() }
                }
                .accessibilityIdentifier("settings.subscription.manage")
                Button(String(localized: "Restore Purchases", bundle: .module)) {
                    Task { await model.restore() }
                }
                .disabled(model.isWorking)
                .accessibilityIdentifier("settings.subscription.restore")
                if let message = model.message {
                    Text(SubscriptionWording.message(message)).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.subscription.message")
                }
            } header: {
                Text(String(localized: "Subscription", bundle: .module, comment: "A settings section title"))
            }
        }

        private var startTitle: String {
            if let product = model.product { return SubscriptionWording.buttonTitle(product) }
            return String(
                localized: "See Subscription Options", bundle: .module,
                comment: "Button that opens the subscription offer when its price is not loaded")
        }
    }

    /// The one in-app notice that the free trial is about to end (E13-S5).
    struct TrialEndingBanner: View {
        let model: SubscriptionModel

        var body: some View {
            if model.showsTrialEndingNotice {
                HStack(spacing: 12) {
                    Text(SubscriptionWording.trialEndingNotice).font(.footnote)
                        .accessibilityIdentifier("trial.notice")
                    Spacer()
                    Button(String(localized: "Subscribe", bundle: .module)) {
                        model.dismissTrialEndingNotice()
                        model.showPaywall()
                    }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("trial.notice.subscribe")
                    Button {
                        model.dismissTrialEndingNotice()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Dismiss", bundle: .module))
                    .accessibilityIdentifier("trial.notice.dismiss")
                }
                .padding(12)
                .background(.thinMaterial)
            }
        }
    }
#endif
