#if os(iOS)
    import SwiftUI

    /// The iPhone and iPad app: Dictate and Settings, as tabs on a phone and a
    /// sidebar on an iPad (E8-S9). The app-switcher snapshot is covered so a
    /// result on screen is never shown there, and a recording started on this screen
    /// stops when the app goes to the background (E8-S4).
    public struct MobileRootView: View {
        enum Tab: Hashable {
            case dictate
            case settings
        }

        let quick: QuickDictationModel
        let settings: MobileSettingsView
        let dictation: DictationSettingsModel
        let actionDictation: ActionDictationController?
        /// The subscription offer is shown over everything when this says so. `nil` in a build without it.
        let subscription: SubscriptionModel?
        /// The first-run setup guide (E8-S10), full screen while it is presented. `nil` in a build without it.
        let setupGuide: SetupGuideModel?
        @State private var tab: Tab = .dictate
        @Environment(\.scenePhase) private var scenePhase

        public init(
            quick: QuickDictationModel, dictation: DictationSettingsModel, settings: MobileSettingsView,
            actionDictation: ActionDictationController? = nil, subscription: SubscriptionModel? = nil,
            setupGuide: SetupGuideModel? = nil
        ) {
            self.setupGuide = setupGuide
            self.subscription = subscription
            self.actionDictation = actionDictation
            self.quick = quick
            self.dictation = dictation
            self.settings = settings
        }

        public var body: some View {
            TabView(selection: $tab) {
                SwiftUI.Tab(String(localized: "Dictate", bundle: .module), systemImage: "mic.fill", value: Tab.dictate)
                {
                    NavigationStack {
                        QuickDictationView(model: quick, dictation: dictation) { tab = .settings }
                            .safeAreaInset(edge: .top) {
                                if let subscription { TrialEndingBanner(model: subscription) }
                            }
                    }
                }
                SwiftUI.Tab(
                    String(localized: "Settings", bundle: .module), systemImage: "gearshape", value: Tab.settings
                ) {
                    NavigationStack { settings }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .overlay {
                if scenePhase != .active { PrivacyCover() }
            }
            .onChange(of: scenePhase) { _, phase in
                // An Action Button dictation is meant to run with another app in front (ADR 0032).
                if phase == .background, actionDictation?.isActive != true { quick.recorder.stopForSystemReason() }
                if phase == .active { quick.startIfRequestedByShortcut() }
            }
            .task { quick.recorder.onOpenSettings = { _ in tab = .settings } }
            .sheet(isPresented: paywallBinding) {
                if let subscription { PaywallView(model: subscription) }
            }
            .fullScreenCover(isPresented: setupGuideBinding) {
                if let setupGuide { SetupGuideView(model: setupGuide) }
            }
            .onChange(of: setupGuide?.isPresented) { _, presented in
                if presented == false { tab = .dictate }
            }
        }

        /// While the guide is up it shows the paywall itself: a sheet here could not appear over it.
        private var paywallBinding: Binding<Bool> {
            Binding(
                get: { setupGuide?.isPresented != true && subscription?.isShowingPaywall == true },
                set: { subscription?.isShowingPaywall = $0 })
        }

        private var setupGuideBinding: Binding<Bool> {
            Binding(
                get: { setupGuide?.isPresented ?? false },
                set: { if !$0, setupGuide?.isPresented == true { setupGuide?.finish() } })
        }
    }

    /// Hides the screen while the app is not active, so the app switcher never shows a result.
    struct PrivacyCover: View {
        var body: some View {
            ZStack {
                Rectangle().fill(.background)
                Image(systemName: "mic.fill").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
#endif
