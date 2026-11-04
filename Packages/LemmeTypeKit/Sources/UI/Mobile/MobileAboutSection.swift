#if os(iOS)
    import Support
    import SwiftUI

    /// Settings › About on iPhone and iPad: the version, the privacy policy and help
    /// pages (opened in Safari only when tapped), and the open-source licences the
    /// app must ship (MIT, whisper.cpp and the Whisper weights).
    struct MobileAboutSection: View {
        private let buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary)

        var body: some View {
            Section(String(localized: "About", bundle: .module, comment: "Settings section: version and legal")) {
                LabeledContent(
                    String(localized: "Version", bundle: .module, comment: "Label: the app's version number"),
                    value: buildInfo.displayString
                )
                .accessibilityIdentifier("settings.version")
                Link(
                    String(localized: "Privacy Policy", bundle: .module, comment: "Link to the privacy policy"),
                    destination: PublicLinks.privacyPolicy
                )
                .accessibilityIdentifier("settings.privacyPolicy")
                Link(
                    String(localized: "Help and Support", bundle: .module, comment: "Link to the help page"),
                    destination: PublicLinks.support
                )
                .accessibilityIdentifier("settings.support")
                NavigationLink(
                    String(
                        localized: "Acknowledgements", bundle: .module,
                        comment: "Opens the open-source licences")
                ) {
                    AcknowledgementsView()
                }
                .accessibilityIdentifier("settings.acknowledgements")
            }
        }
    }

    /// The licence texts (``Acknowledgements``).
    struct AcknowledgementsView: View {
        var body: some View {
            ScrollView {
                Text(verbatim: Acknowledgements.text)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(
                String(localized: "Acknowledgements", bundle: .module, comment: "Opens the open-source licences")
            )
            .accessibilityIdentifier("acknowledgements.text")
        }

    }
#endif
