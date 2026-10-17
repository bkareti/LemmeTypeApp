import SwiftUI

/// Settings › Dictation: the engine and output settings plus vocabulary,
/// replacements, snippets, and modes (E4-S4, E4-S6). Sections share the tab so the settings
/// window keeps its fixed width.
struct DictationTabView: View {
    enum Section: Hashable {
        case engine
        case items(PersonalizationDraft.Kind)
        case modes
    }

    let dictation: DictationSettingsModel
    let personalization: PersonalizationModel
    let modes: ModesSettingsModel
    @State private var section: Section = .engine

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Show", bundle: .module), selection: $section) {
                Text(String(localized: "Engine", bundle: .module)).tag(Section.engine)
                Text(String(localized: "Vocabulary", bundle: .module)).tag(Section.items(.vocabulary))
                Text(String(localized: "Replacements", bundle: .module)).tag(Section.items(.replacement))
                Text(String(localized: "Snippets", bundle: .module)).tag(Section.items(.snippet))
                Text(String(localized: "Modes", bundle: .module)).tag(Section.modes)
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
            case .modes:
                ModesSettingsView(model: modes)
            }
        }
    }
}
