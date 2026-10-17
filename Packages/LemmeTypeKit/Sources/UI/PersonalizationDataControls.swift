import Domain
import SwiftUI
import UniformTypeIdentifiers

/// The exported personalization file (E4-S8): readable JSON.
struct PersonalizationDocument: FileDocument {
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

/// Export, Import, and Delete All for vocabulary, replacements, snippets,
/// modes, and app rules (E4-S8). Files are written only where the user chooses.
struct PersonalizationDataControls: View {
    let personalization: PersonalizationModel
    let modes: ModesSettingsModel
    @State private var exportDocument: PersonalizationDocument?
    @State private var isImporting = false
    @State private var pendingImport: PersonalizationLibrary?
    @State private var isConfirmingDelete = false
    @State private var message: String?

    var body: some View {
        HStack {
            Button(String(localized: "Export…", bundle: .module), action: export)
                .accessibilityIdentifier("personalization.export")
            Button(String(localized: "Import…", bundle: .module)) { isImporting = true }
                .accessibilityIdentifier("personalization.import")
            Spacer()
            Button(String(localized: "Delete All…", bundle: .module), role: .destructive) { isConfirmingDelete = true }
                .accessibilityIdentifier("personalization.deleteAll")
        }
        .controlSize(.small)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument, contentType: .json,
            defaultFilename: String(localized: "LemmeType Personalization", bundle: .module)
        ) { result in
            if case .failure = result { show(PersonalizationError.storageFailure.userMessage) }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            read(url)
        }
        .confirmationDialog(
            importTitle, isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            presenting: pendingImport
        ) { imported in
            Button(String(localized: "Add to Mine", bundle: .module)) {
                let merge = personalization.merge(imported)
                show(
                    String(
                        localized: "Added \(merge.added) items; skipped \(merge.skipped) duplicates.", bundle: .module))
            }
            Button(String(localized: "Replace Mine", bundle: .module), role: .destructive) {
                personalization.replace(with: imported)
                modes.refresh()
                show(String(localized: "Imported \(PersonalizationSummary(imported).total) items.", bundle: .module))
            }
        } message: { imported in
            Text(Self.summary(of: imported))
        }
        .confirmationDialog(
            String(localized: "Delete all personalization?", bundle: .module), isPresented: $isConfirmingDelete
        ) {
            Button(String(localized: "Delete All", bundle: .module), role: .destructive) {
                Task {
                    await personalization.deleteAll()
                    modes.refresh()
                    show(
                        String(
                            localized: "All vocabulary, replacements, snippets, and custom modes were deleted.",
                            bundle: .module))
                }
            }
        } message: {
            Text(
                String(
                    localized:
                        "Vocabulary, replacements, snippets, custom modes, and app rules are removed from this Mac. Export first if you want a copy.",
                    bundle: .module))
        }
        .alert(
            message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button(String(localized: "OK", bundle: .module)) { message = nil }
        }
    }

    private var importTitle: String {
        String(localized: "Import personalization?", bundle: .module)
    }

    private func export() {
        do throws(PersonalizationError) {
            exportDocument = PersonalizationDocument(data: try personalization.exportData())
        } catch {
            show(error.userMessage)
        }
    }

    private func read(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            show(PersonalizationError.invalidFile.userMessage)
            return
        }
        switch personalization.readImport(data) {
        case .success(let library): pendingImport = library
        case .failure(let error): show(error.userMessage)
        }
    }

    private func show(_ text: String) {
        message = text
        AccessibilityNotification.Announcement(text).post()
    }

    static func summary(of library: PersonalizationLibrary) -> String {
        let counts = PersonalizationSummary(library)
        return String(
            localized:
                "\(counts.vocabulary) words, \(counts.replacements) replacements, \(counts.snippets) snippets, \(counts.modes) modes, and \(counts.appRules) app rules. Add them to yours (duplicates are skipped), or replace yours?",
            bundle: .module)
    }
}
