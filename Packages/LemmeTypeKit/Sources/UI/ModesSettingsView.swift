import Domain
import SwiftUI

/// Settings › Personalize › Modes (E4-S6, E4-S7).
struct ModesSettingsView: View {
    let model: ModesSettingsModel
    @State private var editing: DictationMode?
    @State private var pendingDeletion: DictationMode?

    var body: some View {
        Form {
            Section {
                Picker(
                    String(localized: "Default mode", bundle: .module),
                    selection: Binding(get: { model.currentDefault.id }, set: { model.setDefault($0) })
                ) {
                    ForEach(model.modes) { mode in
                        Text(mode.displayName).tag(mode.id)
                    }
                }
                .accessibilityIdentifier("modes.default")
                Text(
                    String(
                        localized:
                            "A mode decides the engine, how text is cleaned up, its style, and whether it’s inserted or only copied. The default is used everywhere without an app rule.",
                        bundle: .module)
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Section(String(localized: "Modes", bundle: .module)) {
                ForEach(model.modes) { mode in
                    modeRow(mode)
                }
                Button(String(localized: "New Mode…", bundle: .module)) {
                    editing = DictationMode(name: "")
                }
                .accessibilityIdentifier("modes.new")
            }
            Section(String(localized: "Use a mode in a specific app", bundle: .module)) {
                ForEach(model.appRules) { row in
                    HStack {
                        Picker(
                            row.applicationName,
                            selection: Binding(get: { row.rule.mode }, set: { model.setMode($0, for: row.rule) })
                        ) {
                            ForEach(model.modes) { mode in
                                Text(mode.displayName).tag(mode.id)
                            }
                        }
                        Button(String(localized: "Remove", bundle: .module)) { model.removeRule(row.id) }
                            .accessibilityLabel(
                                Text(String(localized: "Remove rule for \(row.applicationName)", bundle: .module)))
                    }
                }
                Menu(String(localized: "Add App…", bundle: .module)) {
                    ForEach(model.candidates) { app in
                        Button(app.name) { model.addRule(for: app, mode: model.currentDefault.id) }
                    }
                }
                .accessibilityIdentifier("modes.addApp")
                Text(
                    String(
                        localized:
                            "When you dictate into one of these apps, its mode is used instead of the default. LemmeType only checks which app is in front when you press the shortcut.",
                        bundle: .module)
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refresh() }
        .sheet(item: $editing) { mode in
            ModeEditor(mode: mode, model: model) { editing = nil }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { mode in
            Button(String(localized: "Delete Mode", bundle: .module), role: .destructive) { model.delete(mode.id) }
        } message: { mode in
            Text(deletionMessage(mode))
        }
    }

    private func modeRow(_ mode: DictationMode) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                Text(mode.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !mode.isBuiltIn {
                Button(String(localized: "Edit", bundle: .module)) { editing = mode }
                    .accessibilityLabel(Text(String(localized: "Edit \(mode.displayName)", bundle: .module)))
            }
            Button(String(localized: "Duplicate", bundle: .module)) { model.duplicate(mode) }
                .accessibilityLabel(Text(String(localized: "Duplicate \(mode.displayName)", bundle: .module)))
            if !mode.isBuiltIn {
                Button(String(localized: "Delete", bundle: .module), role: .destructive) { requestDelete(mode) }
                    .accessibilityLabel(Text(String(localized: "Delete \(mode.displayName)", bundle: .module)))
            }
        }
    }

    private func requestDelete(_ mode: DictationMode) {
        if model.deletionImpact(of: mode.id).needsConfirmation {
            pendingDeletion = mode
        } else {
            model.delete(mode.id)
        }
    }

    private var deletionTitle: String {
        String(localized: "Delete “\(pendingDeletion?.displayName ?? "")”?", bundle: .module)
    }

    private func deletionMessage(_ mode: DictationMode) -> String {
        let impact = model.deletionImpact(of: mode.id)
        var lines: [String] = []
        if impact.isDefault {
            lines.append(
                String(localized: "It’s your default mode; Clean Writing becomes the default.", bundle: .module))
        }
        if !impact.applications.isEmpty {
            let apps = impact.applications.formatted(.list(type: .and))
            lines.append(String(localized: "The rules for \(apps) are removed.", bundle: .module))
        }
        return lines.joined(separator: " ")
    }
}

/// Create or edit a custom mode. Saving validates; errors stay in the sheet.
private struct ModeEditor: View {
    let model: ModesSettingsModel
    let dismiss: () -> Void
    @State private var mode: DictationMode
    @State private var error: PersonalizationError?

    init(mode: DictationMode, model: ModesSettingsModel, dismiss: @escaping () -> Void) {
        self.model = model
        self.dismiss = dismiss
        _mode = State(initialValue: mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Form {
                TextField(String(localized: "Name", bundle: .module), text: $mode.name)
                    .accessibilityIdentifier("modes.editor.name")
                Section(String(localized: "Transcription", bundle: .module)) {
                    Picker(String(localized: "Engine", bundle: .module), selection: $mode.engine) {
                        Text(String(localized: "As in Dictation settings", bundle: .module))
                            .tag(RecognitionEngineID?.none)
                        ForEach(model.engines, id: \.self) { engine in
                            Text(engine.displayName).tag(RecognitionEngineID?.some(engine))
                        }
                    }
                    Picker(String(localized: "Language", bundle: .module), selection: $mode.language) {
                        Text(String(localized: "As in Dictation settings", bundle: .module)).tag(String?.none)
                        ForEach(model.languages, id: \.self) { language in
                            Text(Locale.current.localizedString(forIdentifier: language) ?? language)
                                .tag(String?.some(language))
                        }
                    }
                }
                Section(String(localized: "Cleanup", bundle: .module)) {
                    Picker(String(localized: "Writing", bundle: .module), selection: $mode.writingMode) {
                        ForEach(WritingMode.allCases, id: \.self) { writing in
                            Text(writing.displayName).tag(writing)
                        }
                    }
                    if mode.writingMode == .clean {
                        ForEach(CleanupRule.allCases, id: \.self) { rule in
                            Toggle(rule.displayName, isOn: ruleBinding(rule))
                        }
                    }
                }
                Section(String(localized: "Style", bundle: .module)) {
                    Toggle(
                        String(localized: "Use vocabulary and replacements", bundle: .module),
                        isOn: $mode.usesPersonalization)
                    Toggle(String(localized: "Expand snippets", bundle: .module), isOn: $mode.usesSnippets)
                    Toggle(
                        String(localized: "Leave out the final period", bundle: .module),
                        isOn: Binding(
                            get: { mode.finalPunctuation == .omit },
                            set: { mode.finalPunctuation = $0 ? .omit : .keep }))
                }
                Section(String(localized: "Output", bundle: .module)) {
                    Picker(String(localized: "Send text to", bundle: .module), selection: $mode.output) {
                        Text(String(localized: "Insert at the cursor", bundle: .module)).tag(OutputAction.insert)
                        Text(String(localized: "Clipboard only", bundle: .module)).tag(OutputAction.copy)
                    }
                    Toggle(String(localized: "Add a space after the text", bundle: .module), isOn: $mode.appendsSpace)
                }
            }
            .formStyle(.grouped)
            if let error {
                Text(error.userMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("modes.editor.error")
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module), role: .cancel, action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save", bundle: .module)) {
                    error = model.save(mode)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("modes.editor.save")
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460, height: 520)
        .onChange(of: error) { _, error in
            if let error {
                AccessibilityNotification.Announcement(error.userMessage).post()
            }
        }
    }

    private func ruleBinding(_ rule: CleanupRule) -> Binding<Bool> {
        Binding(
            get: { mode.cleanupRules.contains(rule) },
            set: { enabled in
                mode.cleanupRules.removeAll { $0 == rule }
                if enabled { mode.cleanupRules.append(rule) }
            })
    }
}

extension DictationMode {
    /// One line describing what the mode does.
    var summary: String {
        var parts = [writingMode.displayName]
        if finalPunctuation == .omit { parts.append(String(localized: "no final period", bundle: .module)) }
        if !usesPersonalization { parts.append(String(localized: "no vocabulary", bundle: .module)) }
        if output == .copy { parts.append(String(localized: "clipboard only", bundle: .module)) }
        if let engine { parts.append(engine.displayName) }
        return parts.joined(separator: " · ")
    }
}

extension CleanupRule {
    var displayName: String {
        switch self {
        case .spokenPunctuation: String(localized: "Spoken punctuation (“comma”, “new line”)", bundle: .module)
        case .selfCorrection: String(localized: "Self-corrections (“Tuesday—sorry—Wednesday”)", bundle: .module)
        case .fillerWords: String(localized: "Remove “um” and “uh”", bundle: .module)
        case .repeatedWords: String(localized: "Remove repeated words", bundle: .module)
        case .capitalization: String(localized: "Capitalize sentences", bundle: .module)
        case .terminalPunctuation: String(localized: "End with punctuation", bundle: .module)
        }
    }
}
