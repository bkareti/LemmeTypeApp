import Domain
import Observation
import Support

/// The user's personalization library in memory, shared by Settings and the
/// recorder (E4-S1). Every change is validated, applied, and saved at once;
/// a session captures ``library`` when its recording starts, so edits apply
/// from the next dictation.
@MainActor
@Observable
public final class PersonalizationModel {
    public private(set) var library: PersonalizationLibrary = .empty
    /// Why the stored library could not be used, until the user dismisses it.
    public private(set) var loadIssue: PersonalizationError?
    /// The last failed save, if any.
    public private(set) var saveError: PersonalizationError?
    public private(set) var hasLoaded = false

    private let store: any PersonalizationStoring
    private let diagnostics: any DiagnosticsRecording
    private var saveTask: Task<Void, Never>?

    public init(store: any PersonalizationStoring, diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()) {
        self.store = store
        self.diagnostics = diagnostics
    }

    /// Reads the store once at launch.
    public func load() async {
        let result = await store.load()
        library = result.library
        loadIssue = result.issue
        hasLoaded = true
    }

    public func dismissLoadIssue() {
        loadIssue = nil
    }

    // MARK: Changes

    /// Adds or updates an entry. Returns the validation error instead of
    /// saving when the entry is invalid.
    @discardableResult
    public func save(_ entry: VocabularyEntry) -> PersonalizationError? {
        change { library throws(PersonalizationError) in try library.upsert(entry) }
    }

    @discardableResult
    public func save(_ replacement: Replacement) -> PersonalizationError? {
        change { library throws(PersonalizationError) in try library.upsert(replacement) }
    }

    @discardableResult
    public func save(_ snippet: Snippet) -> PersonalizationError? {
        change { library throws(PersonalizationError) in try library.upsert(snippet) }
    }

    public func removeVocabulary(_ id: VocabularyEntry.ID) {
        change { $0.removeVocabulary(id) }
    }

    public func removeReplacement(_ id: Replacement.ID) {
        change { $0.removeReplacement(id) }
    }

    public func removeSnippet(_ id: Snippet.ID) {
        change { $0.removeSnippet(id) }
    }

    /// Replaces the whole library (import, E4-S8) and saves it.
    public func replace(with library: PersonalizationLibrary) {
        self.library = library
        persist()
    }

    /// Waits for pending saves. For tests and app termination.
    public func settle() async {
        await saveTask?.value
    }

    @discardableResult
    private func change(
        _ mutation: (inout PersonalizationLibrary) throws(PersonalizationError) -> Void
    ) -> PersonalizationError? {
        var updated = library
        do {
            try mutation(&updated)
        } catch {
            return error
        }
        guard updated != library else { return nil }
        library = updated
        persist()
        return nil
    }

    /// Saves in order: each save waits for the previous one.
    private func persist() {
        let previous = saveTask
        let snapshot = library
        let store = self.store
        saveTask = Task { [weak self] in
            await previous?.value
            do throws(PersonalizationError) {
                try await store.save(snapshot)
                self?.saveError = nil
            } catch {
                self?.saveError = error
                self?.diagnostics.record(
                    .personalization, "personalization.save-failed", ["error": .id(error.identifier)])
            }
        }
    }
}
