import Domain
import Foundation

/// The personalization library as one JSON file (ADR 0020):
/// `<directory>/library.json`, owner-only (0600 in a 0700 directory), replaced
/// atomically. A file that can't be read is renamed aside — never overwritten —
/// so nothing the user wrote is lost silently.
public actor FilePersonalizationStore: PersonalizationStoring {
    public nonisolated let directory: URL
    private let diagnostics: any DiagnosticsRecording
    private let now: @Sendable () -> Date

    public init(
        directory: URL,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directory = directory
        self.diagnostics = diagnostics
        self.now = now
    }

    /// Application Support/LemmeType/Personalization.
    public static func makeDefault(diagnostics: any DiagnosticsRecording) -> FilePersonalizationStore {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FilePersonalizationStore(
            directory: support.appendingPathComponent("LemmeType/Personalization", isDirectory: true),
            diagnostics: diagnostics)
    }

    public nonisolated var fileURL: URL { directory.appendingPathComponent("library.json") }

    public func load() -> PersonalizationLoad {
        guard let data = FileManager.default.contents(atPath: fileURL.path) else {
            return PersonalizationLoad(library: .empty)
        }
        do throws(PersonalizationError) {
            let library = try PersonalizationArchive.decode(data)
            diagnostics.record(
                .personalization, "personalization.loaded",
                [
                    "vocabulary": .count(library.vocabulary.count), "replacements": .count(library.replacements.count),
                    "snippets": .count(library.snippets.count),
                ])
            return PersonalizationLoad(library: library)
        } catch {
            let issue: PersonalizationError = error == .unsupportedVersion ? .unsupportedVersion : .unreadable
            moveAside()
            diagnostics.record(.personalization, "personalization.load-failed", ["error": .id(issue.identifier)])
            Log.personalization.error("Personalization file unusable: \(issue.identifier, privacy: .public)")
            return PersonalizationLoad(library: .empty, issue: issue)
        }
    }

    public func save(_ library: PersonalizationLibrary) throws(PersonalizationError) {
        let data = try PersonalizationArchive(library).encoded()
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Log.personalization.error("Personalization save failed")
            throw .storageFailure
        }
    }

    public func deleteAll() throws(PersonalizationError) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        do {
            for file in files where file.lastPathComponent.hasPrefix("library") {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            throw .storageFailure
        }
        diagnostics.record(.personalization, "personalization.deleted")
    }

    /// Renames an unusable file to `library-unreadable-<timestamp>.json`.
    private func moveAside() {
        let stamp = Int(now().timeIntervalSince1970)
        let aside = directory.appendingPathComponent("library-unreadable-\(stamp).json")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: fileURL, to: aside)
    }
}
