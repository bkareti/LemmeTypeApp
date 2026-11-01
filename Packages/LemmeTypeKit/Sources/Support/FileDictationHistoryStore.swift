import Domain
import Foundation

/// The dictation history as one JSON file (ADR 0025):
/// `<directory>/history.json`, owner-only (0600 file in a 0700 directory),
/// replaced atomically. Nothing is created until the first save, so with
/// history off no file or folder exists. A file that can't be read is renamed
/// aside — never overwritten — so nothing is lost silently.
public actor FileDictationHistoryStore: DictationHistoryStoring {
    public nonisolated let directory: URL
    private let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    /// Application Support/LemmeType/History.
    public static func makeDefault() -> FileDictationHistoryStore {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FileDictationHistoryStore(
            directory: support.appendingPathComponent("LemmeType/History", isDirectory: true))
    }

    public nonisolated var fileURL: URL { directory.appendingPathComponent("history.json") }

    public func load() -> DictationHistoryLoad {
        guard let data = FileManager.default.contents(atPath: fileURL.path) else {
            return DictationHistoryLoad(history: .empty)
        }
        do throws(DictationHistoryError) {
            return DictationHistoryLoad(history: try DictationHistoryArchive.decode(data))
        } catch {
            moveAside()
            Log.history.error("History file unusable: \(error.identifier, privacy: .public)")
            return DictationHistoryLoad(history: .empty, issue: error)
        }
    }

    public func save(_ history: DictationHistory) throws(DictationHistoryError) {
        let data = try DictationHistoryArchive(history).encoded()
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Log.history.error("History save failed")
            throw .storageFailure
        }
    }

    public func deleteAll() throws(DictationHistoryError) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        do {
            for file in files where file.lastPathComponent.hasPrefix("history") {
                try FileManager.default.removeItem(at: file)
            }
            // Leave no empty folder behind.
            if (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            throw .storageFailure
        }
    }

    /// Renames an unusable file to `history-unreadable-<timestamp>.json`.
    private func moveAside() {
        let stamp = Int(now().timeIntervalSince1970)
        let aside = directory.appendingPathComponent("history-unreadable-\(stamp).json")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: fileURL, to: aside)
    }
}
