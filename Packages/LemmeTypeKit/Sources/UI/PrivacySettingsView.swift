import SwiftUI

/// Settings › Privacy (E6-S4, E6-S5): an overview in plain words, and the
/// dictation history. Sections share the tab, chosen from a pop-up menu, so
/// the fixed window width is kept.
struct PrivacySettingsView: View {
    enum Section: Hashable {
        case overview
        case history
    }

    let history: HistorySettingsModel
    let overview: PrivacyOverviewModel
    let openContextSettings: () -> Void
    @State private var section: Section = .overview

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Show:", bundle: .module), selection: $section) {
                Text(
                    String(
                        localized: "Overview", bundle: .module,
                        comment: "Noun: a summary page of how LemmeType uses your data")
                ).tag(Section.overview)
                Text(
                    String(
                        localized: "History", bundle: .module,
                        comment: "Noun: the list of dictations the user chose to keep")
                ).tag(Section.history)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 20)
            .accessibilityIdentifier("privacy.section")
            switch section {
            case .overview:
                PrivacyOverviewView(model: overview, openContextSettings: openContextSettings)
            case .history:
                HistorySettingsView(model: history)
            }
        }
    }
}
