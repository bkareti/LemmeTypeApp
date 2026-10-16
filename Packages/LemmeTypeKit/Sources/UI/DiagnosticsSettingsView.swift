import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsSettingsView: View {
    let model: DiagnosticsModel

    var body: some View {
        Form {
            Section {
                Text(
                    String(
                        localized: """
                            A diagnostics report helps with support. It contains the app and macOS \
                            versions, Mac model, permission states, and recent app events such as \
                            “recording started” or error codes.
                            """,
                        bundle: .module))
                Text(
                    String(
                        localized: """
                            It never contains audio, dictated text, text from other apps, clipboard \
                            contents, or device and app names. Nothing is sent anywhere — you choose \
                            where to save it.
                            """,
                        bundle: .module)
                )
                .foregroundStyle(.secondary)
                Button(String(localized: "Preview Report…", bundle: .module)) { model.preparePreview() }
                    .accessibilityIdentifier("diagnostics.preview")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(get: { model.preview != nil }, set: { if !$0 { model.closePreview() } })) {
            DiagnosticsPreviewSheet(model: model)
        }
    }
}

private struct DiagnosticsPreviewSheet: View {
    let model: DiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Diagnostics Report Preview", bundle: .module))
                .font(.headline)
            Text(String(localized: "This is exactly what will be saved.", bundle: .module))
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(model.preview ?? "")
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("diagnostics.content")
            }
            .frame(minHeight: 260)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            if let error = model.saveError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) { model.closePreview() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save…", bundle: .module)) { chooseLocation() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("diagnostics.save")
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }

    private func chooseLocation() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.suggestedFileName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.save(to: url)
        }
    }
}
