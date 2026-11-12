import Domain
import Foundation

/// The subscription summary in the App Group shared by the iPhone app and its keyboard (E13-S5): its kind and
/// when it ends, and nothing that identifies anyone. Excluded from backups, never logged, and removed by
/// Delete All Local Data.
public struct AppGroupEntitlementSummaryStore: EntitlementSummaryStoring {
    private static let fileName = "entitlement-summary.json"
    private let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    public static func makeDefault() -> AppGroupEntitlementSummaryStore {
        AppGroupEntitlementSummaryStore(
            directory: FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroupKeyboardHandoffStore.appGroup))
    }

    private var fileURL: URL? { directory?.appending(path: Self.fileName) }

    public func write(_ summary: EntitlementSummary) {
        guard var url = fileURL, let data = try? JSONEncoder().encode(summary) else { return }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            Log.delivery.error("Could not update the subscription summary")
        }
    }

    public func read() -> EntitlementSummary? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EntitlementSummary.self, from: data)
    }

    public func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
