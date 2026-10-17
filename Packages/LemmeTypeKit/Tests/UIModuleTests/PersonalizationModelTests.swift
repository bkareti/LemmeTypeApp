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
