#if os(iOS)
    import Domain
    import SwiftUI

    /// The first-run setup guide on iPhone and iPad (E8-S10), full screen over the app. One step at a time,
    /// with a progress bar, Back, and Close. On the microphone step, before iOS has asked, the only way on is
    /// Continue, which shows the system prompt (App Review Guideline 5.1.1).
    public struct SetupGuideView: View {
        @Bindable var model: SetupGuideModel
        @State private var movesForward = true
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        public init(model: SetupGuideModel) {
            self.model = model
        }

        public var body: some View {
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    page
                        .id(model.step)
                        .transition(pageTransition)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                bottomBar
            }
            .background(Color(uiColor: .systemBackground))
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45), value: model.step)
            .modelDownloadConfirmation(model.models)
            .sheet(isPresented: paywallBinding) {
                if let subscription = model.subscription { PaywallView(model: subscription) }
            }
            .sheet(isPresented: consentBinding) {
                if let cloudSpeech = model.cloudSpeech { CloudSpeechConsentView(model: cloudSpeech) }
            }
            .task { await model.models.refresh() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("setup.guide")
        }

        // MARK: Frame

        private var pageTransition: AnyTransition {
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .move(edge: movesForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: movesForward ? .leading : .trailing).combined(with: .opacity))
        }

        /// Close and Back are hidden on the microphone step until iOS has asked (Guideline 5.1.1).
        private var canLeaveThisStep: Bool { model.step != .microphone || model.hasAskedForMicrophone }

        private var topBar: some View {
            HStack(spacing: 16) {
                // Left out, not just hidden, when it may not be used; the frame keeps the bar from moving.
                ZStack {
                    Color.clear
                    if model.canGoBack && canLeaveThisStep {
                        Button {
                            movesForward = false
                            model.back()
                        } label: {
                            Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                        }
                        .accessibilityLabel(Text(String(localized: "Back", bundle: .module)))
                        .accessibilityIdentifier("setup.back")
                    }
                }
                .frame(width: 28, height: 28)
                progressBar
                ZStack {
                    Color.clear
                    if canLeaveThisStep {
                        Button(action: model.finish) {
                            Image(systemName: "xmark").font(.title3.weight(.semibold))
                        }
                        .accessibilityLabel(
                            Text(
                                String(
                                    localized: "Close Setup", bundle: .module,
                                    comment: "Closes the first-run setup guide"))
                        )
                        .accessibilityIdentifier("setup.close")
                    }
                }
                .frame(width: 28, height: 28)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }

        private var progressBar: some View {
            HStack(spacing: 6) {
                ForEach(Array(model.steps.enumerated()), id: \.element) { index, _ in
                    Capsule()
                        .fill(index <= model.position ? Color.setupJade : Color.secondary.opacity(0.25))
                        .frame(height: 6)
                        .frame(maxWidth: index == model.position ? 44 : 22)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel(
                Text(
                    String(
                        localized: "Step \(model.position + 1) of \(model.steps.count)", bundle: .module,
                        comment: "Where the user is in the setup guide")))
        }

        private var bottomBar: some View {
            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(.setupJade)
                .accessibilityIdentifier("setup.primary")
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .padding(.top, 8)
        }

        private var primaryTitle: String {
            switch model.step {
            case .welcome:
                String(localized: "Get Started", bundle: .module, comment: "First button of the setup guide")
            case .microphone where !model.hasAskedForMicrophone:
                String(localized: "Continue", bundle: .module)
            case .done: String(localized: "Start Dictating", bundle: .module)
            default: String(localized: "Next", bundle: .module, comment: "Moves to the next setup step")
            }
        }

        private func primaryAction() {
            movesForward = true
            if model.step == .microphone, !model.hasAskedForMicrophone {
                Task { await model.allowMicrophone() }
            } else {
                model.next()
            }
        }

        // MARK: Sheets

        private var paywallBinding: Binding<Bool> {
            Binding(
                get: { model.subscription?.isShowingPaywall ?? false },
                set: { model.subscription?.isShowingPaywall = $0 })
        }

        private var consentBinding: Binding<Bool> {
            Binding(
                get: { model.cloudSpeech?.isShowingConsent ?? false },
                set: { model.cloudSpeech?.isShowingConsent = $0 })
        }
    }
#endif
