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
                            "Back Tap lists only your own shortcuts, so make one first: in the Shortcuts app, tap +, add the “Dictate Anywhere” action from LemmeType, and tap Done. Then choose it in Settings › Accessibility › Touch › Back Tap › Double Tap.",
                        bundle: .module,
                        comment: "How to run Dictate Anywhere from Back Tap")
                ) {
                    BackTapIllustration()
                } footer: {
                    Link(String(localized: "Open Shortcuts", bundle: .module), destination: PublicLinks.newShortcut)
                        .accessibilityIdentifier("settings.shortcut-guide.open-shortcuts")
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
#endif
