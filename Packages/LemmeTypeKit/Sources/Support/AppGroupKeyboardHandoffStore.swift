import Domain
import Foundation

/// The file in the App Group shared by the iPhone app and its keyboard (ADR 0032).
/// It holds one status and at most one finished dictation, for seconds. It is
/// excluded from backups and never logged.
public struct AppGroupKeyboardHandoffStore: KeyboardHandoffPublishing {
    public static let appGroup = "group.com.lemmetype.LemmeType"
    private static let fileName = "keyboard-handoff.json"

    private let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    public static func makeDefault() -> AppGroupKeyboardHandoffStore {
        AppGroupKeyboardHandoffStore(
            directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup))
    }

    private var fileURL: URL? { directory?.appending(path: Self.fileName) }

    public func publish(_ handoff: KeyboardHandoff) {
        guard var url = fileURL, let data = try? JSONEncoder().encode(handoff) else { return }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            Log.delivery.error("Could not update the keyboard handoff")
        }
    }

    public func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// The current handoff, or idle when nothing has been left.
    public func read() -> KeyboardHandoff {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
            let handoff = try? JSONDecoder().decode(KeyboardHandoff.self, from: data)
        else { return .idle }
        return handoff
    }
}
