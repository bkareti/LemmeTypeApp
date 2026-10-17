import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E4-S1/E4-S4: the shared personalization model validates, saves, and
/// hands each recording a snapshot.
@MainActor
struct PersonalizationModelTests {
    @Test func loadsTheStoredLibraryAndReportsAnUnreadableFile() async throws {
        let stored = try PersonalizationLibrary(
            vocabulary: [VocabularyEntry(term: "LemmeType")], replacements: [], snippets: [])
        let model = PersonalizationModel(store: FakePersonalizationStore(library: stored, issue: .unreadable))
        #expect(!model.hasLoaded)
        await model.load()
        #expect(model.library == stored)
        #expect(model.loadIssue == .unreadable)
        model.dismissLoadIssue()
        #expect(model.loadIssue == nil)
    }

    @Test func validChangesAreSavedInvalidOnesAreNot() async throws {
        let store = FakePersonalizationStore()
        let model = PersonalizationModel(store: store)
        await model.load()

        #expect(model.save(Replacement(spoken: "my email", written: "pat@example.com")) == nil)
        #expect(model.save(Replacement(spoken: "MY EMAIL", written: "other")) == .duplicate(.spoken))
        #expect(model.save(Snippet(trigger: "", expansion: "x")) == .empty(.trigger))
        let entry = VocabularyEntry(term: "LemmeType")
        #expect(model.save(entry) == nil)
        model.removeVocabulary(entry.id)
        await model.settle()

        #expect(model.library.replacements.count == 1)
        #expect(model.library.vocabulary.isEmpty)
        #expect(store.library == model.library)
        #expect(store.saveCount == 3)
    }

    @Test func saveFailureIsReported() async {
        let store = FakePersonalizationStore()
        store.failSaves(with: .storageFailure)
        let model = PersonalizationModel(store: store)
        model.save(VocabularyEntry(term: "LemmeType"))
        await model.settle()
        #expect(model.saveError == .storageFailure)
        #expect(model.library.vocabulary.count == 1)  // kept in memory for this launch
    }

    @Test func recordingCapturesTheLibraryWhenItStarts() async throws {
        let model = PersonalizationModel(store: FakePersonalizationStore())
        let source = FakeAudioSource()
        let processor = RecordingSpy()
        let coordinator = RecordingCoordinator(
            capture: AudioCaptureService(
                source: source,
                storage: AudioSessionStorage(
                    directory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("LemmeTypeTests-Personalization-\(UUID().uuidString)")),
                permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: FakeFeedback(), preferences: FakePreferences(),
            finishedDisplay: .milliseconds(10), personalization: { model.library })

        model.save(VocabularyEntry(term: "Before"))
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        model.save(VocabularyEntry(term: "During"))  // edited mid-recording
        source.emitTone(seconds: 0.3)
        coordinator.handle(.stop)
        await coordinator.settle()

        #expect(processor.libraries.map { $0.vocabulary.map(\.term) } == [["Before"]])
    }
}

/// E4-S4: the add/edit sheet's draft saves every kind and reports errors.
@MainActor
struct PersonalizationDraftTests {
    @Test func savesEachKindFromTheTwoFields() async {
        let model = PersonalizationModel(store: FakePersonalizationStore())
        var word = PersonalizationDraft.new(.vocabulary)
        word.primary = "LemmeType"
        word.secondary = "lemme type, lemon type"
        #expect(word.save(in: model) == nil)
        var replacement = PersonalizationDraft.new(.replacement)
        replacement.primary = "my email"
        replacement.secondary = "pat@example.com"
        #expect(replacement.save(in: model) == nil)
        var snippet = PersonalizationDraft.new(.snippet)
        snippet.primary = "sign off"
        snippet.secondary = "Best,\nPat"
        #expect(snippet.save(in: model) == nil)

        #expect(model.library.vocabulary.first?.soundsLike == ["lemme type", "lemon type"])
        #expect(model.library.replacements.first?.written == "pat@example.com")
        #expect(model.library.snippets.first?.expansion == "Best,\nPat")
    }

    @Test func editingKeepsTheIdAndInvalidInputIsNotSaved() async throws {
        let model = PersonalizationModel(store: FakePersonalizationStore())
        model.save(Replacement(spoken: "my email", written: "a@example.com"))
        var edit = PersonalizationDraft(try #require(model.library.replacements.first))
        #expect(!edit.isNew)
        edit.secondary = "b@example.com"
        #expect(edit.save(in: model) == nil)
        #expect(model.library.replacements.map(\.written) == ["b@example.com"])

        edit.primary = " "
        #expect(edit.save(in: model) == .empty(.spoken))
        #expect(model.library.replacements.map(\.spoken) == ["my email"])
    }

    @Test func everyErrorHasAMessageWithoutTheRejectedText() {
        let errors: [PersonalizationError] =
            PersonalizationField.allCases.flatMap { [.empty($0), .tooLong($0, limit: 9), .duplicate($0)] }
            + PersonalizationKind.allCases.map { .limitReached($0, limit: 9) }
            + [.tooManySpellings(limit: 5), .notFound, .unreadable, .unsupportedVersion, .invalidFile, .storageFailure]
        for error in errors {
            #expect(!error.userMessage.isEmpty)
        }
    }
}

/// E4-S8: export, import, and Delete All through the shared model.
@MainActor
struct PersonalizationDataTests {
    private func filled(_ store: FakePersonalizationStore) -> PersonalizationModel {
        let model = PersonalizationModel(store: store)
        model.save(VocabularyEntry(term: "LemmeType"))
        model.save(Snippet(trigger: "sign off", expansion: "Best,\nPat"))
        return model
    }

    @Test func exportedFileImportsIntoAnEmptyLibraryExactly() async throws {
        let source = filled(FakePersonalizationStore())
        let data = try source.exportData()

        let target = PersonalizationModel(store: FakePersonalizationStore())
        let imported = try target.readImport(data).get()
        target.replace(with: imported)
        #expect(target.library == source.library)
    }

    @Test func invalidFilesChangeNothing() async {
        let model = filled(FakePersonalizationStore())
        let before = model.library
        #expect(model.readImport(Data("nope".utf8)) == .failure(.invalidFile))
        let newer = Data(#"{"format":"com.lemmetype.personalization","formatVersion":9}"#.utf8)
        #expect(model.readImport(newer) == .failure(.unsupportedVersion))
        #expect(model.library == before)
    }

    @Test func mergeReportsAddedAndSkipped() throws {
        let model = filled(FakePersonalizationStore())
        let other = try PersonalizationLibrary(
            vocabulary: [VocabularyEntry(term: "lemmetype"), VocabularyEntry(term: "Kubernetes")], replacements: [],
            snippets: [])
        let merge = model.merge(other)
        #expect(merge.added == 1)
        #expect(merge.skipped == 1)
        #expect(model.library.vocabulary.map(\.term) == ["LemmeType", "Kubernetes"])
    }

    @Test func deleteAllEmptiesTheStoreAndResetsACustomDefault() async {
        let store = FakePersonalizationStore()
        let model = filled(store)
        let preferences = FakePreferences()
        let modes = ModesSettingsModel(personalization: model, preferences: preferences)
        let chat = DictationMode(name: "Chat")
        modes.save(chat)
        modes.setDefault(chat.id)

        await model.deleteAll()
        modes.refresh()
        #expect(model.library == .empty)
        #expect(store.deleteCount == 1)
        #expect(store.library == .empty)
        #expect(modes.currentDefault == .clean)
        #expect(preferences.dictationMode == .clean)
    }
}
