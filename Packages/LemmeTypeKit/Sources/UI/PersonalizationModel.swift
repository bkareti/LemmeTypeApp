import Domain
import Foundation
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

    /// Adds or updates a custom mode (E4-S5).
    @discardableResult
    public func save(_ mode: DictationMode) -> PersonalizationError? {
        change { library throws(PersonalizationError) in try library.upsert(mode) }
    }

    /// Removes a custom mode and the app rules that used it.
    public func removeMode(_ id: DictationModeID) {
        change { $0.removeMode(id) }
    }

    @discardableResult
    public func save(_ rule: AppModeRule) -> PersonalizationError? {
        change { library throws(PersonalizationError) in try library.upsert(rule) }
    }

    public func removeAppRule(_ id: AppModeRule.ID) {
        change { $0.removeAppRule(id) }
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

    // MARK: Export, import, delete (E4-S8)

    /// The whole library as a versioned JSON file.
    public func exportData() throws(PersonalizationError) -> Data {
        let data = try PersonalizationArchive(library).encoded()
        diagnostics.record(.personalization, "personalization.exported", ["items": .count(Self.count(library))])
        return data
    }

    /// Reads an import file without changing anything.
    public func readImport(_ data: Data) -> Result<PersonalizationLibrary, PersonalizationError> {
        do throws(PersonalizationError) {
            return .success(try PersonalizationArchive.decode(data))
        } catch {
            diagnostics.record(.personalization, "personalization.import-rejected", ["error": .id(error.identifier)])
            return .failure(error)
        }
    }

    /// Adds what doesn't clash; returns how many items were added and skipped.
    @discardableResult
    public func merge(_ imported: PersonalizationLibrary) -> PersonalizationMerge {
        let merge = library.merging(imported)
        library = merge.library
        persist()
        diagnostics.record(
            .personalization, "personalization.imported",
            ["strategy": .id("merge"), "added": .count(merge.added), "skipped": .count(merge.skipped)])
        return merge
    }

    /// Replaces everything with `imported`.
    public func replace(with imported: PersonalizationLibrary) {
        library = imported
        persist()
        diagnostics.record(
            .personalization, "personalization.imported",
            ["strategy": .id("replace"), "added": .count(Self.count(imported)), "skipped": .count(0)])
    }

    /// Deletes the stored file and every copy moved aside, and empties the library.
    public func deleteAll() async {
        await saveTask?.value
        saveTask = nil
        do throws(PersonalizationError) {
            try await store.deleteAll()
            library = .empty
            loadIssue = nil
            saveError = nil
        } catch {
            saveError = error
        }
    }

    private static func count(_ library: PersonalizationLibrary) -> Int {
        PersonalizationSummary(library).total
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
