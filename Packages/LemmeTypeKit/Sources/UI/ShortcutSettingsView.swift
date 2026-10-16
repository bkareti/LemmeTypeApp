import Domain
import SwiftUI

struct ShortcutSettingsView: View {
    let model: ShortcutSettingsModel
    @State private var recorder = ShortcutRecorder()

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Dictation shortcut", bundle: .module)) {
                    HStack {
                        let label =
                            model.isRecording
                            ? String(localized: "Type a shortcut…", bundle: .module) : model.shortcut.displayString
                        Text(label)
                            .monospaced()
                            .accessibilityIdentifier("shortcut.current")
                            // A new identity per value; otherwise the styled text's
                            // accessibility value stays stale for VoiceOver.
                            .id(label)
                        Button(
                            model.isRecording
                                ? String(localized: "Cancel", bundle: .module)
                                : String(localized: "Change…", bundle: .module)
                        ) {
                            model.isRecording ? stopRecording() : startRecording()
                        }
                        .accessibilityIdentifier("shortcut.record")
                    }
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("shortcut.error")
                }
                if model.shortcut != .defaultDictation {
                    Button(String(localized: "Use Default (⌥Space)", bundle: .module)) { model.resetToDefault() }
                }
            }
            Section {
                Picker(
                    String(localized: "Mode", bundle: .module),
                    selection: Binding(get: { model.mode }, set: { model.setMode($0) })
                ) {
                    Text(String(localized: "Push to Talk — hold to dictate", bundle: .module))
                        .tag(ActivationMode.pushToTalk)
                    Text(String(localized: "Toggle — press to start and stop", bundle: .module))
                        .tag(ActivationMode.toggle)
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("shortcut.mode")
                Text(String(localized: "Press Esc while dictating to cancel.", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section(String(localized: "Try it", bundle: .module)) {
                Text(model.lastActivity ?? String(localized: "Press your shortcut to test it.", bundle: .module))
                    .accessibilityIdentifier("shortcut.lastActivity")
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        model.startRecording()
        recorder.start(
            onShortcut: { shortcut in
                recorder.stop()
                model.recorded(shortcut)
            },
            onCancel: stopRecording
        )
    }

    private func stopRecording() {
        recorder.stop()
        model.cancelRecording()
    }
}
