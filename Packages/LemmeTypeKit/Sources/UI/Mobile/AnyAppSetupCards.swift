#if os(iOS)
    import SwiftUI

    /// One setup step with a moving picture above its words (E8-S10).
    struct SetupCard<Illustration: View, Footer: View>: View {
        let title: String
        let text: String
        @ViewBuilder let illustration: () -> Illustration
        @ViewBuilder let footer: () -> Footer

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                illustration()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(.fill.quinary, in: .rect(cornerRadius: 18))
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                footer()
            }
            .accessibilityElement(children: .contain)
        }
    }

    extension SetupCard where Footer == EmptyView {
        init(title: String, text: String, @ViewBuilder illustration: @escaping () -> Illustration) {
            self.init(title: title, text: text, illustration: illustration, footer: { EmptyView() })
        }
    }

    /// How to dictate into another app from the keyboard, the Action Button, or Back Tap (E8-S7, ADR 0032),
    /// as animated cards. Both buttons run the "Dictate Anywhere" shortcut, which records with the current app
    /// still in front. Back Tap lists only shortcuts in the person's own library, so that one needs a shortcut
    /// made in the Shortcuts app first. Shown in the setup guide and in Settings.
    struct AnyAppSetupCards: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                SetupCard(
                    title: String(localized: "1. Add the keyboard", bundle: .module),
                    text: String(
                        localized:
                            "Settings › General › Keyboard › Keyboards › Add New Keyboard › LemmeType. It does not need Full Access. Switch to it with the globe key in the app you are typing in.",
                        bundle: .module,
                        comment: "Step 1 of setting up dictation into other apps")
                ) {
                    KeyboardIllustration()
                }
                SetupCard(
                    title: String(localized: "2. Action Button", bundle: .module),
                    text: String(
                        localized:
                            "Settings › Action Button › Shortcut › Choose a Shortcut › LemmeType › “Dictate Anywhere”.",
                        bundle: .module,
                        comment: "How to put Dictate Anywhere on the Action Button")
                        + " "
                        + String(
                            localized: "Only on iPhone models with an Action Button.", bundle: .module,
                            comment: "Shown under the Action Button setup step")
                ) {
                    ActionButtonIllustration()
                }
                SetupCard(
                    title: String(localized: "3. Back Tap (optional)", bundle: .module),
                    text: String(
                        localized:
                            "Back Tap can run only shortcuts from your own library, so LemmeType is not listed there until you add one.",
                        bundle: .module,
                        comment: "Why Back Tap needs a shortcut made in the Shortcuts app first")
                ) {
                    BackTapIllustration()
                } footer: {
                    BackTapSteps()
                }
                Text(
                    String(
                        localized:
                            "Press once to start and again to stop. You stay in the app you were using, and the text goes where you were typing. Your iPhone must be unlocked. “Start Dictating” opens LemmeType instead.",
                        bundle: .module,
                        comment: "Footnote under the Action Button and Back Tap steps")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.shortcut-guide")
        }
    }

    /// Making the "Dictate Anywhere" shortcut and choosing it in Back Tap, one step per line. Written for both
    /// Shortcuts layouts: iOS 26 (+, Add Action, Done) and iOS 27, which opens on "Describe a shortcut" with
    /// Edit and saves with the back arrow.
    struct BackTapSteps: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                step(1) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            String(
                                localized: "Open the Shortcuts app.", bundle: .module,
                                comment: "Back Tap setup, step 1"))
                        Link(destination: PublicLinks.newShortcut) {
                            Label(
                                String(localized: "Open Shortcuts", bundle: .module),
                                systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.bordered)
                        .tint(.setupJade)
                        .accessibilityIdentifier("settings.shortcut-guide.open-shortcuts")
                    }
                }
                step(2) {
                    Text(
                        String(
                            localized:
                                "If it asks you to describe a shortcut, tap Edit. Otherwise tap + to make a new shortcut.",
                            bundle: .module, comment: "Back Tap setup, step 2"))
                }
                step(3) {
                    Text(
                        String(
                            localized: "Search for “Dictate Anywhere” and tap it.", bundle: .module,
                            comment: "Back Tap setup, step 3"))
                }
                step(4) {
                    Text(
                        String(
                            localized: "Tap ‹ or Done to save it. It is named “Dictate Anywhere”.", bundle: .module,
                            comment: "Back Tap setup, step 4"))
                }
                step(5) {
                    Text(
                        String(
                            localized:
                                "In Settings › Accessibility › Touch › Back Tap › Double Tap, scroll to the bottom and choose “Dictate Anywhere” under Shortcuts.",
                            bundle: .module, comment: "Back Tap setup, step 5"))
                }
            }
            .font(.subheadline)
            .padding(.top, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.shortcut-guide.back-tap-steps")
        }

        private func step<Content: View>(_ number: Int, @ViewBuilder content: () -> Content) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number, format: .number)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.setupJade, in: .circle)
                    .accessibilityHidden(true)
                content()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
#endif
