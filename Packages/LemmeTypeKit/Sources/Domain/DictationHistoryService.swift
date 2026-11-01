import Foundation

/// Records, ages out, and deletes the dictation history (E6-S3, ADR 0025).
///
/// With retention off it never touches the store, so nothing is created on
/// disk. Sessions that must not be recorded are skipped here, in one place:
/// voice edits, excluded and sensitive apps, empty or oversized results.
public actor DictationHistoryService: DictationHistoryManaging {
    private let store: any DictationHistoryStoring
    private let preferences: any AppPreferences
    private let diagnostics: any DiagnosticsRecording
    private let now: @Sendable () -> Date
    private var loaded: DictationHistory?
    private var issue: DictationHistoryError?

    public init(
        store: any DictationHistoryStoring,
        preferences: any AppPreferences,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.preferences = preferences
        self.diagnostics = diagnostics
        self.now = now
    }

    // MARK: Recording

    public func record(_ text: String, for session: DictationSession, delivery: HistoryDelivery) async {
        let retention = preferences.historyRetention
        guard retention.isOn, session.purpose == .dictation, mayRecord(session) else { return }
        let accepted = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accepted.isEmpty, accepted.count <= DictationHistory.maximumTextLength else { return }

        var history = await current()
        let entry = DictationHistoryEntry(
            createdAt: now(), text: accepted, mode: session.dictationMode.id.rawValue,
            language: session.language, delivery: delivery)
        history.append(entry)
        let removed = history.purge(for: retention, now: now())
        do {
            try await store.save(history)
            loaded = history
            diagnostics.record(
                .history, "history.recorded",
                ["entries": .count(history.count), "retention": .id(retention.identifier), "expired": .count(removed)])
        } catch {
            diagnostics.record(.history, "history.save-failed", ["error": .id(error.identifier)])
        }
    }

    /// Not recorded: excluded apps and the built-in sensitive apps (ADR 0025).
    private func mayRecord(_ session: DictationSession) -> Bool {
        guard let bundleIdentifier = session.target?.bundleIdentifier else { return true }
        if ContextPolicy.isSensitive(bundleIdentifier) { return false }
        return !preferences.contextExcludedApplications.contains(bundleIdentifier)
    }

    // MARK: Reading

    public func snapshot() async -> DictationHistorySnapshot {
        let retention = preferences.historyRetention
        guard retention.isOn else {
            // Off: show what is still stored (a user who just turned it off has
            // chosen to keep nothing), but never create anything.
            let existing = await current()
            return DictationHistorySnapshot(retention: retention, entries: existing.entries, issue: issue)
        }
        await purgeExpired()
        let history = await current()
        return DictationHistorySnapshot(retention: retention, entries: history.entries, issue: issue)
    }

    public func entriesRemoved(by retention: HistoryRetention) async -> Int {
        let history = await current()
        return retention == .off ? history.count : history.expiredCount(for: retention, now: now())
    }

    /// Removes entries the current retention has expired. Safe to call often.
    public func purgeExpired() async {
        let retention = preferences.historyRetention
        guard retention.isOn else { return }
        var history = await current()
        let removed = history.purge(for: retention, now: now())
        guard removed > 0 else { return }
        do {
            try await store.save(history)
            loaded = history
            diagnostics.record(.history, "history.purged", ["removed": .count(removed)])
        } catch {
            diagnostics.record(.history, "history.save-failed", ["error": .id(error.identifier)])
        }
    }

    // MARK: Changing

    public func apply(_ retention: HistoryRetention) async throws(DictationHistoryError) {
        preferences.historyRetention = retention
        diagnostics.record(.history, "history.retention-changed", ["retention": .id(retention.identifier)])
        if retention == .off {
            try await deleteAll()
        } else {
            await purgeExpired()
        }
    }

    public func delete(_ id: UUID) async throws(DictationHistoryError) {
        var history = await current()
        guard history.remove(id: id) else { return }
        try await store.save(history)
        loaded = history
        diagnostics.record(.history, "history.deleted", ["entries": .count(history.count)])
    }

    public func deleteAll() async throws(DictationHistoryError) {
        try await store.deleteAll()
        loaded = .empty
        issue = nil
        diagnostics.record(.history, "history.cleared")
    }

    public func exportData() async throws(DictationHistoryError) -> Data {
        try DictationHistoryArchive(await current()).encoded()
    }

    // MARK: Loading

    private func current() async -> DictationHistory {
        if let loaded { return loaded }
        let load = await store.load()
        if let problem = load.issue {
            diagnostics.record(.history, "history.load-failed", ["error": .id(problem.identifier)])
        }
        loaded = load.history
        issue = load.issue
        return load.history
    }
}
