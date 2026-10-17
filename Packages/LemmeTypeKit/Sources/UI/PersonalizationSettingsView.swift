import Domain
import SwiftUI

/// Settings › Personalize › vocabulary, replacements, and snippets (E4-S4).
struct PersonalizationSettingsView: View {
    let model: PersonalizationModel
    @Binding var kind: PersonalizationDraft.Kind
    @State private var draft: PersonalizationDraft?

    var body: some View {
        Form {
            if let issue = model.loadIssue {
                Section {
                    Label(issue.userMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button(String(localized: "OK", bundle: .module)) { model.dismissLoadIssue() }
                }
            }
            if let error = model.saveError {
                Section {
                    Label(error.userMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            Section {
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(rows) { row in
                    rowView(row)
                }
                HStack {
                    Button(addTitle) { draft = .new(kind) }
                        .accessibilityIdentifier("personalization.add")
                    Spacer()
                    Text(countText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("personalization.count")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $draft) { draft in
            PersonalizationEditor(draft: draft, model: model) { self.draft = nil }
        }
    }

    // MARK: Rows

    private struct Row: Identifiable {
        let id: UUID
        let title: String
        let detail: String
        let draft: PersonalizationDraft
    }

    private var rows: [Row] {
        switch kind {
        case .vocabulary:
            model.library.vocabulary.map {
                Row(id: $0.id, title: $0.term, detail: $0.soundsLike.joined(separator: ", "), draft: .init($0))
            }
        case .replacement:
            model.library.replacements.map {
                Row(id: $0.id, title: $0.spoken, detail: "→ \($0.written)", draft: .init($0))
            }
        case .snippet:
            model.library.snippets.map {
                Row(id: $0.id, title: $0.trigger, detail: $0.expansion, draft: .init($0))
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(String(localized: "Edit", bundle: .module)) { draft = row.draft }
                .accessibilityLabel(Text(String(localized: "Edit \(row.title)", bundle: .module)))
            Button(String(localized: "Delete", bundle: .module), role: .destructive) { delete(row) }
                .accessibilityLabel(Text(String(localized: "Delete \(row.title)", bundle: .module)))
        }
    }

    private func delete(_ row: Row) {
        switch kind {
        case .vocabulary: model.removeVocabulary(row.id)
        case .replacement: model.removeReplacement(row.id)
        case .snippet: model.removeSnippet(row.id)
        }
    }

    // MARK: Text

    private var explanation: String {
        switch kind {
        case .vocabulary:
            String(
                localized:
                    "Names and terms you use. LemmeType listens for them and always spells them your way. Add what you hear instead under “sounds like”.",
                bundle: .module)
        case .replacement:
            String(
                localized:
                    "Say a phrase and LemmeType writes something else — “my email” can become your address. Whole words only, in every mode.",
                bundle: .module)
        case .snippet:
            String(
                localized:
                    "Say only the trigger, and the saved text is inserted exactly as written. A trigger inside a longer sentence never expands.",
                bundle: .module)
        }
    }

    private var addTitle: String {
        switch kind {
        case .vocabulary: String(localized: "Add Word…", bundle: .module)
        case .replacement: String(localized: "Add Replacement…", bundle: .module)
        case .snippet: String(localized: "Add Snippet…", bundle: .module)
        }
    }

    private var countText: String {
        let (count, limit) =
            switch kind {
            case .vocabulary: (model.library.vocabulary.count, PersonalizationLimits.vocabularyEntries)
            case .replacement: (model.library.replacements.count, PersonalizationLimits.replacements)
            case .snippet: (model.library.snippets.count, PersonalizationLimits.snippets)
            }
        return String(localized: "\(count) of \(limit)", bundle: .module)
    }
}

/// The add/edit sheet. Saving validates first; an invalid entry stays open
/// with the reason shown.
private struct PersonalizationEditor: View {
    let model: PersonalizationModel
    let dismiss: () -> Void
    @State private var draft: PersonalizationDraft
    @State private var error: PersonalizationError?

    init(draft: PersonalizationDraft, model: PersonalizationModel, dismiss: @escaping () -> Void) {
        self.model = model
        self.dismiss = dismiss
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Form {
                TextField(primaryLabel, text: $draft.primary)
                    .accessibilityIdentifier("personalization.editor.primary")
                if draft.kind == .snippet {
                    LabeledContent(secondaryLabel) {
                        TextEditor(text: $draft.secondary)
                            .font(.body)
                            .frame(minHeight: 90)
                            .accessibilityLabel(Text(secondaryLabel))
                            .accessibilityIdentifier("personalization.editor.secondary")
                    }
                } else {
                    TextField(secondaryLabel, text: $draft.secondary)
                        .accessibilityIdentifier("personalization.editor.secondary")
                }
            }
            if let error {
                Text(error.userMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("personalization.editor.error")
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module), role: .cancel, action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save", bundle: .module)) {
                    error = draft.save(in: model)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("personalization.editor.save")
            }
        }
        .padding(20)
        .frame(width: 420)
        .onChange(of: error) { _, error in
            if let error {
                AccessibilityNotification.Announcement(error.userMessage).post()
            }
        }
    }

    private var title: String {
        switch (draft.kind, draft.isNew) {
        case (.vocabulary, true): String(localized: "New Word", bundle: .module)
        case (.vocabulary, false): String(localized: "Edit Word", bundle: .module)
        case (.replacement, true): String(localized: "New Replacement", bundle: .module)
        case (.replacement, false): String(localized: "Edit Replacement", bundle: .module)
        case (.snippet, true): String(localized: "New Snippet", bundle: .module)
        case (.snippet, false): String(localized: "Edit Snippet", bundle: .module)
        }
    }

    private var primaryLabel: String {
        switch draft.kind {
        case .vocabulary: PersonalizationField.term.displayName
        case .replacement: PersonalizationField.spoken.displayName
        case .snippet: PersonalizationField.trigger.displayName
        }
    }

    private var secondaryLabel: String {
        switch draft.kind {
        case .vocabulary: String(localized: "Sounds like (comma-separated, optional)", bundle: .module)
        case .replacement: PersonalizationField.written.displayName
        case .snippet: PersonalizationField.expansion.displayName
        }
    }
}
