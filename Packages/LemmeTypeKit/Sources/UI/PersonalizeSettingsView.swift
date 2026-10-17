import SwiftUI

/// Settings › Personalize: one tab for everything Epic 4 adds, so the
/// settings window keeps its width (E4-S4).
struct PersonalizeSettingsView: View {
    let personalization: PersonalizationModel
    @State private var section: PersonalizationDraft.Kind = .vocabulary

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Show", bundle: .module), selection: $section) {
                Text(String(localized: "Vocabulary", bundle: .module)).tag(PersonalizationDraft.Kind.vocabulary)
                Text(String(localized: "Replacements", bundle: .module)).tag(PersonalizationDraft.Kind.replacement)
                Text(String(localized: "Snippets", bundle: .module)).tag(PersonalizationDraft.Kind.snippet)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 16)
            .accessibilityIdentifier("personalize.section")
            PersonalizationSettingsView(model: personalization, kind: $section)
        }
    }
}
