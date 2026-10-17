import Domain
import Foundation
import Support
import Testing

/// E4-S1: the personalization file is private, atomic, and never overwritten
/// when it can't be read.
struct FilePersonalizationStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-Personalization-\(UUID().uuidString)", isDirectory: true)

    private func sample() throws -> PersonalizationLibrary {
        try PersonalizationLibrary(
            vocabulary: [VocabularyEntry(term: "LemmeType", soundsLike: ["lemme type"])],
            replacements: [Replacement(spoken: "my email", written: "pat@example.com")],
            snippets: [Snippet(trigger: "sign off", expansion: "Best,\nPat")])
    }

    private func permissions(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    @Test func missingFileLoadsAnEmptyLibrary() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let load = await FilePersonalizationStore(directory: directory).load()
        #expect(load == PersonalizationLoad(library: .empty))
    }

    @Test func saveThenLoadRoundTripsWithOwnerOnlyPermissions() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FilePersonalizationStore(directory: directory)
        let library = try sample()
        try await store.save(library)

        #expect(await FilePersonalizationStore(directory: directory).load() == PersonalizationLoad(library: library))
        #expect(try permissions(store.fileURL) == 0o600)
        #expect(try permissions(directory) == 0o700)
        // Saving again replaces the file; no temporary files are left behind.
        try await store.save(.empty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["library.json"])
        #expect(await store.load().library == .empty)
    }

    @Test func unreadableFileIsMovedAsideNotOverwritten() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FilePersonalizationStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
        let corrupt = Data("{ not json".utf8)
        try corrupt.write(to: store.fileURL)

        let load = await store.load()
        #expect(load == PersonalizationLoad(library: .empty, issue: .unreadable))
        let aside = directory.appendingPathComponent("library-unreadable-1000.json")
        #expect(FileManager.default.contents(atPath: aside.path) == corrupt)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))

        // A later save writes a new file and keeps the old one.
        try await store.save(try sample())
        #expect(FileManager.default.contents(atPath: aside.path) == corrupt)
    }

    @Test func newerFormatIsReportedAndKept() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FilePersonalizationStore(directory: directory, now: { Date(timeIntervalSince1970: 7) })
        try Data(#"{"format":"com.lemmetype.personalization","formatVersion":99}"#.utf8).write(to: store.fileURL)

        #expect(await store.load().issue == .unsupportedVersion)
        #expect(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("library-unreadable-7.json").path))
    }

    @Test func deleteAllRemovesTheLibraryAndCopiesMovedAside() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FilePersonalizationStore(directory: directory)
        try await store.save(try sample())
        try Data("x".utf8).write(to: directory.appendingPathComponent("library-unreadable-1.json"))

        try await store.deleteAll()
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(await store.load().library == .empty)
    }

    @Test func diagnosticsRecordCountsNeverText() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = DiagnosticsBuffer()
        let store = FilePersonalizationStore(directory: directory, diagnostics: diagnostics)
        try await store.save(try sample())
        _ = await store.load()
        let events = diagnostics.snapshot()
        #expect(events.contains { $0.name == "personalization.loaded" && $0.attributes["vocabulary"] == .count(1) })
        let report = String(describing: events).lowercased()
        #expect(!report.contains("lemme") && !report.contains("pat@") && !report.contains("best"))
    }
}
