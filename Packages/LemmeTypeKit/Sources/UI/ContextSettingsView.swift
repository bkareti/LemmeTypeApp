import Domain
import SwiftUI

/// Settings › Context (E3-S6).
struct ContextSettingsView: View {
    let model: ContextSettingsModel
    let shortcut: ShortcutSettingsModel
    @State private var recorder = ShortcutRecorder()

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "Use text near the cursor to fit dictation in", bundle: .module),
                    isOn: Binding(get: { model.usesFormattingContext }, set: { model.setFormattingContext($0) })
                )
                .accessibilityIdentifier("context.formatting")
                Text(
                    String(
                        localized:
                            "When you press the dictation shortcut, LemmeType reads up to 240 characters before the cursor and 40 after it, once, to fix spacing, capitals, and periods. It stays on this Mac, is never saved, and is forgotten when the dictation ends.",
                        bundle: .module)
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Section(String(localized: "Voice editing", bundle: .module)) {
                Toggle(
                    String(localized: "Edit selected text by voice", bundle: .module),
                    isOn: Binding(get: { model.allowsVoiceEditing }, set: { model.setVoiceEditing($0) })
                )
                .accessibilityIdentifier("context.voiceEditing")
                if model.allowsVoiceEditing {
                    editShortcutRow
                }
                Text(
                    String(
                        localized:
                            "Select text, hold the shortcut, and say what to change — “make this shorter”, “fix the grammar”, “turn this into a list”, or “translate to Spanish”. Only the selection is read, and Apple’s on-device model rewrites it on this Mac.",
                        bundle: .module)
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                if let availability = model.rewriterAvailability {
                    Label(
                        availability.userMessage,
                        systemImage: availability.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(availability.isReady ? .green : .orange)
                    .accessibilityIdentifier("context.modelStatus")
                }
            }
            Section(String(localized: "Never read text in", bundle: .module)) {
                ForEach(model.excludedApplications) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Button(String(localized: "Remove", bundle: .module)) { model.include(app.bundleIdentifier) }
                            .accessibilityLabel(Text(String(localized: "Remove \(app.name)", bundle: .module)))
                    }
                }
                Menu(String(localized: "Add App…", bundle: .module)) {
                    ForEach(model.candidates) { app in
                        Button(app.name) { model.exclude(app) }
                    }
                }
                .accessibilityIdentifier("context.addApp")
                Text(sensitiveNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Password fields are never read in any app.", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshApplications()
            model.refreshAvailability()
        }
        .onDisappear { stopRecording() }
    }

    private var sensitiveNote: String {
        let installed = model.sensitiveApplications
        let names =
            installed.isEmpty
            ? String(localized: "password managers and Keychain Access", bundle: .module)
            : installed.formatted(.list(type: .and))
        return String(localized: "Always excluded: \(names).", bundle: .module)
    }

    private var editShortcutRow: some View {
        LabeledContent(String(localized: "Voice editing shortcut", bundle: .module)) {
            HStack {
                let label =
                    shortcut.isRecordingEdit
                    ? String(localized: "Type a shortcut…", bundle: .module)
                    : (shortcut.editShortcut?.displayString ?? "—")
                Text(label)
                    .monospaced()
                    .accessibilityIdentifier("context.editShortcut")
                    .id(label)
                Button(
                    shortcut.isRecordingEdit
                        ? String(localized: "Cancel", bundle: .module)
                        : String(localized: "Change…", bundle: .module)
                ) {
                    shortcut.isRecordingEdit ? stopRecording() : startRecording()
                }
                if shortcut.editShortcut != .defaultVoiceEdit, !shortcut.isRecordingEdit {
                    Button(String(localized: "Use Default (⌥⇧Space)", bundle: .module)) {
                        shortcut.resetEditToDefault()
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let error = shortcut.editErrorMessage {
                Text(error).font(.callout).foregroundStyle(.red).offset(y: 18)
            }
        }
    }

    private func startRecording() {
        shortcut.startRecordingEdit()
        recorder.start(
            onShortcut: { recorded in
                recorder.stop()
                shortcut.recordedEdit(recorded)
            },
            onCancel: stopRecording
        )
    }

    private func stopRecording() {
        recorder.stop()
        shortcut.cancelRecordingEdit()
    }
}
