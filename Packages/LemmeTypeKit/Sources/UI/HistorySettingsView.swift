import Domain
import SwiftUI
import UniformTypeIdentifiers

/// The exported history file: readable, versioned JSON.
struct HistoryDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Settings › Privacy › History: off by default, with a retention period,
/// the saved dictations, Export, and Delete All (E6-S4).
struct HistorySettingsView: View {
    let model: HistorySettingsModel
    @State private var exportDocument: HistoryDocument?
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                String(localized: "Keep a history of what I dictate", bundle: .module),
                isOn: Binding(get: { model.isOn }, set: { enabled in Task { await model.setOn(enabled) } })
            )
            .accessibilityIdentifier("history.toggle")

            Picker(
                String(localized: "Keep for:", bundle: .module),
                selection: Binding(
                    get: { model.retention }, set: { value in Task { await model.choose(value) } })
            ) {
                Text(String(localized: "1 day", bundle: .module)).tag(HistoryRetention.oneDay)
                Text(String(localized: "1 week", bundle: .module)).tag(HistoryRetention.oneWeek)
                Text(String(localized: "1 month", bundle: .module)).tag(HistoryRetention.oneMonth)
                Text(String(localized: "Until I delete it", bundle: .module)).tag(HistoryRetention.untilDeleted)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!model.isOn)
            .accessibilityIdentifier("history.retention")

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("history.explanation")

            if model.issue != nil {
                Text(
                    String(
                        localized:
                            "The saved history couldn’t be read, so it was set aside and a new one was started. The old file is still on this Mac.",
                        bundle: .module)
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("history.issue")
            }

            entriesList

            HStack {
                Button(String(localized: "Export…", bundle: .module), action: export)
                    .disabled(model.entries.isEmpty)
                    .accessibilityIdentifier("history.export")
                Spacer()
                Button(String(localized: "Delete All…", bundle: .module), role: .destructive) {
                    isConfirmingDeleteAll = true
                }
                .disabled(model.entries.isEmpty)
                .accessibilityIdentifier("history.deleteAll")
            }
            .controlSize(.small)
        }
        .padding(20)
        .task { await model.refresh() }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument, contentType: .json,
            defaultFilename: String(localized: "LemmeType History", bundle: .module)
        ) { result in
            if case .failure = result {
                announce(String(localized: "The history couldn’t be exported. Try again.", bundle: .module))
            }
        }
        .confirmationDialog(
            String(localized: "Delete all saved dictations?", bundle: .module), isPresented: $isConfirmingDeleteAll
        ) {
            Button(
                String(
                    localized: "Delete All", bundle: .module,
                    comment: "Button label (verb): remove every item of this kind"), role: .destructive
            ) {
                Task {
                    await model.deleteAll()
                    announce(model.message)
                }
            }
        } message: {
            Text(
                String(
                    localized: "They are removed from this Mac. Export first if you want a copy.", bundle: .module))
        }
        .confirmationDialog(
            pendingTitle,
            isPresented: Binding(
                get: { model.pendingChange != nil }, set: { if !$0 { model.cancelPendingChange() } }),
            presenting: model.pendingChange
        ) { _ in
            Button(String(localized: "Delete and Continue", bundle: .module), role: .destructive) {
                Task {
                    await model.confirmPendingChange()
                    announce(model.message)
                }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { model.cancelPendingChange() }
        } message: { change in
            Text(pendingMessage(change))
        }
    }

    // MARK: Parts

    private var entriesList: some View {
        Group {
            if model.entries.isEmpty {
                Text(
                    model.isOn
                        ? String(localized: "Nothing saved yet. Your next dictation will appear here.", bundle: .module)
                        : String(localized: "History is off. Nothing is being saved.", bundle: .module)
                )
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("history.empty")
            } else {
                List(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                    HistoryRow(entry: entry, index: index, model: model, announce: announce)
                }
                .accessibilityIdentifier("history.list")
            }
        }
        .frame(minHeight: 110, maxHeight: .infinity)
    }

    private var explanation: String {
        model.isOn
            ? String(
                localized:
                    "Saved on this Mac only, in a private file. It holds the text you inserted or copied, with the time. It never holds audio, the app you used, or the text around your cursor. Time Machine backs it up if you use it.",
                bundle: .module)
            : String(
                localized:
                    "Off. LemmeType keeps no record of what you dictate. If you turn this on, only the text you insert or copy is saved, on this Mac.",
                bundle: .module)
    }

    private var pendingTitle: String {
        guard let change = model.pendingChange else { return "" }
        return change.retention == .off
            ? String(localized: "Turn off history?", bundle: .module)
            : String(localized: "Use a shorter period?", bundle: .module)
    }

    private func pendingMessage(_ change: HistorySettingsModel.PendingChange) -> String {
        String(
            localized: "This deletes \(change.removes) saved dictations from this Mac. This can’t be undone.",
            bundle: .module)
    }

    private func export() {
        Task {
            if let data = await model.exportData() { exportDocument = HistoryDocument(data: data) }
        }
    }

    private func announce(_ text: String?) {
        guard let text else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}

/// One saved dictation: when, a one-line preview, Copy, and Delete.
private struct HistoryRow: View {
    let entry: DictationHistoryEntry
    let index: Int
    let model: HistorySettingsModel
    let announce: (String?) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(HistorySettingsModel.when(entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    await model.copy(entry)
                    announce(model.message)
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(
                String(
                    localized: "Copy", bundle: .module, comment: "Button label (verb): put the text on the clipboard")
            )
            .accessibilityLabel(
                String(
                    localized: "Copy", bundle: .module, comment: "Button label (verb): put the text on the clipboard")
            )
            .accessibilityIdentifier("history.copy.\(index)")
            Button {
                Task {
                    await model.delete(entry)
                    announce(model.message)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Delete", bundle: .module, comment: "Button label (verb): remove one item"))
            .accessibilityLabel(
                String(localized: "Delete", bundle: .module, comment: "Button label (verb): remove one item")
            )
            .accessibilityIdentifier("history.delete.\(index)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.row.\(index)")
    }
}
