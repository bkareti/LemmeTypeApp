import Domain
import Foundation
import Support
import Testing

/// ADR 0032: the file shared with the keyboard.
struct AppGroupKeyboardHandoffStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-Handoff-\(UUID().uuidString)", isDirectory: true)

    private func makeStore() throws -> AppGroupKeyboardHandoffStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppGroupKeyboardHandoffStore(directory: directory)
    }

    @Test func aPublishedHandoffCanBeRead() throws {
        let store = try makeStore()
        let handoff = KeyboardHandoff.ready(text: "Hello", at: Date(timeIntervalSinceReferenceDate: 5))
        store.publish(handoff)
        #expect(store.read() == handoff)
    }

    @Test func clearingErasesTheFile() throws {
        let store = try makeStore()
        store.publish(.ready(text: "Hello"))
        store.clear()
        #expect(store.read() == .idle)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func aMissingOrDamagedFileReadsAsIdle() throws {
        let store = try makeStore()
        #expect(store.read() == .idle)
        try Data("not json".utf8).write(to: directory.appending(path: "keyboard-handoff.json"))
        #expect(store.read() == .idle)
    }

    @Test func noSharedFolderDoesNothing() {
        let store = AppGroupKeyboardHandoffStore(directory: nil)
        store.publish(.ready(text: "Hello"))
        #expect(store.read() == .idle)
    }

    @Test func theFileIsExcludedFromBackups() throws {
        let store = try makeStore()
        store.publish(.ready(text: "Hello"))
        let url = directory.appending(path: "keyboard-handoff.json")
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
}
