import Domain
import Foundation
import Testing

@testable import Support

/// E6-S3: the history file is private, atomic, and never overwrites what it
/// cannot read. Directories use the `LemmeTypeTests-` prefix (privacy-check).
struct FileDictationHistoryStoreTests {
    static func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-History-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    static let sampleHistory = DictationHistory(entries: [
        DictationHistoryEntry(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), text: "Stored text", mode: "clean",
            language: "en-US", delivery: .inserted)
    ])

    static func sample() -> DictationHistory { sampleHistory }

    static func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    @Test func loadingCreatesNothing() async {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let store = FileDictationHistoryStore(directory: directory)

        let load = await store.load()

        #expect(load.history.isEmpty)
        #expect(load.issue == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func savedHistoryRoundTrips() async throws {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let store = FileDictationHistoryStore(directory: directory)

        try await store.save(Self.sample())

        let load = await FileDictationHistoryStore(directory: directory).load()
        #expect(load.history == Self.sample())
        #expect(load.issue == nil)
    }

    @Test func theFileIsOwnerOnlyInAnOwnerOnlyDirectory() async throws {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let store = FileDictationHistoryStore(directory: directory)

        try await store.save(Self.sample())

        func mode(_ url: URL) throws -> Int {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
        }
        #expect(try mode(store.fileURL) == 0o600)
        #expect(try mode(directory) == 0o700)
    }

    @Test func anUnreadableFileIsMovedAsideNotOverwritten() async throws {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let store = FileDictationHistoryStore(directory: directory, now: { Date(timeIntervalSince1970: 42) })
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)

        let load = await store.load()

        #expect(load.issue == .unreadable)
        #expect(load.history.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        let aside = directory.appendingPathComponent("history-unreadable-42.json")
        #expect(try Data(contentsOf: aside) == Data("not json".utf8))
    }

    @Test func aNewerVersionIsMovedAsideAndReported() async throws {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let store = FileDictationHistoryStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"format":"com.lemmetype.history","formatVersion":99,"entries":[]}"#.utf8).write(to: store.fileURL)

        let load = await store.load()

        #expect(load.issue == .unsupportedVersion)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func deleteAllRemovesTheFileTheCopiesAndTheFolder() async throws {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let store = FileDictationHistoryStore(directory: directory)
        try await store.save(Self.sample())
        try Data("old".utf8).write(to: directory.appendingPathComponent("history-unreadable-1.json"))

        try await store.deleteAll()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        try await store.deleteAll()  // nothing left: still fine
    }

    @Test func deleteAllLeavesOtherFilesAlone() async throws {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let store = FileDictationHistoryStore(directory: directory)
        try await store.save(Self.sample())
        let other = directory.appendingPathComponent("keep.txt")
        try Data("x".utf8).write(to: other)

        try await store.deleteAll()

        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}
