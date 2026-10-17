import SwiftUI

/// Settings › Dictation: the engine and output settings plus vocabulary,
/// replacements, and snippets (E4-S4). Sections share the tab so the settings
/// window keeps its fixed width.
struct DictationTabView: View {
    enum Section: Hashable {
        case engine
        case items(PersonalizationDraft.Kind)
    }

    let dictation: DictationSettingsModel
    let personalization: PersonalizationModel
    @State private var section: Section = .engine

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Show", bundle: .module), selection: $section) {
                Text(String(localized: "Engine", bundle: .module)).tag(Section.engine)
                Text(String(localized: "Vocabulary", bundle: .module)).tag(Section.items(.vocabulary))
                Text(String(localized: "Replacements", bundle: .module)).tag(Section.items(.replacement))
                Text(String(localized: "Snippets", bundle: .module)).tag(Section.items(.snippet))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 12)
            .accessibilityIdentifier("dictation.section")
            switch section {
            case .engine:
                DictationSettingsView(model: dictation)
            case .items(let kind):
                PersonalizationSettingsView(
                    model: personalization, kind: Binding(get: { kind }, set: { section = .items($0) }))
            }
        }
    }
}
