#if os(iOS)
    import Domain
    import SwiftUI

    /// Switches a translation review to the language that was spoken and back (E12-S6).
    /// A cloud session asks first, because the recording is uploaded again.
    struct ReviewLanguageSwitch: View {
        let model: QuickDictationModel
        @State private var confirmsUpload = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                if model.canShowSpokenLanguage {
                    Button(model.showSpokenLanguageTitle, systemImage: "character.bubble") {
                        if model.spokenLanguageNeedsUpload {
                            confirmsUpload = true
                        } else {
                            model.showSpokenLanguage()
                        }
                    }
                    .accessibilityIdentifier("quick.spoken-language")
                } else if model.canShowEnglish {
                    Button(
                        String(
                            localized: "Show English", bundle: .module,
                            comment: "Review button: go back to the English translation"),
                        systemImage: "character.bubble", action: model.showEnglish
                    )
                    .accessibilityIdentifier("quick.english")
                }
                if let failure = model.spokenLanguageFailureMessage {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("quick.spoken-language-failure")
                }
            }
            .confirmationDialog(
                model.showSpokenLanguageTitle, isPresented: $confirmsUpload, titleVisibility: .visible
            ) {
                Button(
                    String(
                        localized: "Send Again", bundle: .module,
                        comment: "Confirms uploading the recording to the cloud again"),
                    action: model.showSpokenLanguage)
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
            } message: {
                Text(
                    String(
                        localized:
                            "This sends the recording to the cloud speech service again and uses some of your cloud allowance.",
                        bundle: .module,
                        comment: "Explains, before uploading again, what showing the spoken language costs"))
            }
        }
    }
#endif
