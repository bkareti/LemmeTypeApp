import Domain
import Foundation
import Observation

/// Settings › Privacy › History (E6-S4): the retention choice and the saved
/// dictations. Shortening or switching off asks first, with the number of
/// entries it would delete; Cancel changes nothing.
@MainActor
@Observable
public final class HistorySettingsModel {
    /// A retention change waiting for the user's confirmation.
    public struct PendingChange: Equatable, Sendable {
        public let retention: HistoryRetention
        /// Entries the change deletes.
        public let removes: Int
    }

    public private(set) var retention: HistoryRetention = .off
    /// Newest first.
    public private(set) var entries: [DictationHistoryEntry] = []
    /// Why the stored file could not be read, until the pane is refreshed.
    public private(set) var issue: DictationHistoryError?
    public private(set) var pendingChange: PendingChange?
    /// The result of the last action, for the pane to show and announce.
    public private(set) var message: String?
    public private(set) var hasLoaded = false

    private let history: any DictationHistoryManaging
    private let copier: any TextCopying
    /// What turning History on chooses; the shortest period that is still useful.
    public static let defaultRetention = HistoryRetention.oneWeek

    public init(history: any DictationHistoryManaging, copier: any TextCopying) {
        self.history = history
        self.copier = copier
    }

    public var isOn: Bool { retention.isOn }

    /// Reads the current choice and entries, removing expired ones.
    public func refresh() async {
        let snapshot = await history.snapshot()
        retention = snapshot.retention
        entries = snapshot.entries
        issue = snapshot.issue
        hasLoaded = true
    }

    // MARK: Retention

    /// Turns History on (with ``defaultRetention``) or off.
    public func setOn(_ enabled: Bool) async {
        await choose(enabled ? Self.defaultRetention : .off)
    }

    /// Applies `new` at once, or asks first when it would delete entries.
    public func choose(_ new: HistoryRetention) async {
        guard new != retention else { return }
        let removes = await history.entriesRemoved(by: new)
        if removes > 0 {
            pendingChange = PendingChange(retention: new, removes: removes)
        } else {
            await apply(new)
        }
    }

    public func confirmPendingChange() async {
        guard let change = pendingChange else { return }
        pendingChange = nil
        await apply(change.retention)
        message = String(
            localized: "Deleted \(change.removes) saved dictations.", bundle: .module,
            comment: "Shown after a shorter history period or turning history off deleted entries")
    }

    public func cancelPendingChange() {
        pendingChange = nil
    }

    private func apply(_ new: HistoryRetention) async {
        do {
            try await history.apply(new)
        } catch {
            message = String(localized: "History couldn’t be changed. Try again.", bundle: .module)
        }
        await refresh()
    }

    // MARK: Entries

    public func copy(_ entry: DictationHistoryEntry) async {
        await copier.copy(entry.text)
        message = String(localized: "Copied.", bundle: .module)
    }

    public func delete(_ entry: DictationHistoryEntry) async {
        do {
            try await history.delete(entry.id)
            message = String(localized: "Deleted.", bundle: .module)
        } catch {
            message = String(localized: "History couldn’t be changed. Try again.", bundle: .module)
        }
        await refresh()
    }

    public func deleteAll() async {
        do {
            try await history.deleteAll()
            message = String(localized: "All saved dictations were deleted.", bundle: .module)
        } catch {
            message = String(localized: "History couldn’t be changed. Try again.", bundle: .module)
        }
        await refresh()
    }

    /// The JSON file the user may save; `nil` (with a message) if it can't be made.
    public func exportData() async -> Data? {
        do {
            return try await history.exportData()
        } catch {
            message = String(localized: "The history couldn’t be exported. Try again.", bundle: .module)
            return nil
        }
    }

    public func showMessage(_ text: String) {
        message = text
    }

    public func dismissMessage() {
        message = nil
    }
}
