import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E12-S6: showing a translation's recording in the language that was spoken, and back.
@MainActor
struct RecordingCoordinatorSpokenLanguageTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let processor = RecordingSpy()
    private let copier = FakeTextDelivery()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-SpokenLanguage-\(UUID().uuidString)", isDirectory: true))
    private let english = "Send me the file tomorrow"
    private let telugu = "నాకు file రేపు పంపు"

    private func makeCoordinator(language: String = "te") -> RecordingCoordinator {
        let preferences = FakePreferences(dictationLanguage: language)
        preferences.speechOutput = .english
        return RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage,
                permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: feedback, preferences: preferences, textCopier: copier,
            finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }

    private func speak(_ coordinator: RecordingCoordinator) async {
        coordinator.handle(.start(nil))
        await coordinator.settle()
        source.emitTone(seconds: 0.5)
        coordinator.handle(.stop)
        await coordinator.settle()
    }

    private func held(_ issue: DictationIssue, _ text: String?) -> DictationOutcome {
        .needsAttention(issue, engine: .cloud, alternatives: [], transcript: text)
    }

    @Test func showingTheSpokenLanguageRecognisesTheSameRecordingAgainWithOriginalOutput() async {
        defer { cleanUp() }
        processor.script([held(.reviewTranslation, english), held(.reviewText, telugu)])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        #expect(coordinator.canShowSpokenLanguage)
        #expect(coordinator.spokenLanguageNeedsUpload, "a cloud session uploads again")
        #expect(coordinator.reviewSpokenLanguage == "te")

        coordinator.showSpokenLanguage()
        await coordinator.settle()

        #expect(processor.outputs == [.english, .original])
        #expect(processor.languages == ["te", "te"])
        #expect(processor.consumed.count == 2 && processor.consumed[0].fileURL == processor.consumed[1].fileURL)
        #expect(coordinator.attention == .reviewText)
        #expect(coordinator.reviewText == telugu)
        #expect(coordinator.canShowEnglishTranslation && !coordinator.canShowSpokenLanguage)
        #expect(copier.copied.isEmpty, "nothing is copied by switching")
    }

    @Test func showEnglishBringsBackTheTranslationWithoutProcessingAgain() async {
        defer { cleanUp() }
        processor.script([held(.reviewTranslation, english), held(.reviewText, telugu)])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        coordinator.showSpokenLanguage()
        await coordinator.settle()

        coordinator.showEnglishTranslation()
        await coordinator.settle()

        #expect(coordinator.attention == .reviewTranslation)
        #expect(coordinator.reviewText == english)
        #expect(!coordinator.attentionActions.contains(.retry), "the recording is gone: no Translate Again")
        #expect(coordinator.canShowSpokenLanguage && !coordinator.spokenLanguageNeedsUpload)

        coordinator.showSpokenLanguage()
        await coordinator.settle()
        #expect(coordinator.reviewText == telugu)
        #expect(processor.consumed.count == 2, "both texts are in memory: nothing is uploaded again")
    }

    @Test func aFailureShowsTheTranslationAgainWithItsChoicesAndTheReason() async {
        defer { cleanUp() }
        processor.script([held(.reviewTranslation, english), held(.recognitionFailed(.cloudOffline), nil)])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        let choices = coordinator.attentionActions

        coordinator.showSpokenLanguage()
        await coordinator.settle()

        #expect(coordinator.attention == .reviewTranslation)
        #expect(coordinator.reviewText == english)
        #expect(coordinator.attentionActions == choices)
        #expect(coordinator.spokenLanguageFailure == .recognitionFailed(.cloudOffline))
        #expect(coordinator.canShowSpokenLanguage, "it can be tried again")
    }

    @Test func cancelWhileUploadingShowsTheTranslationAgain() async {
        defer { cleanUp() }
        processor.script([held(.reviewTranslation, english), held(.reviewText, telugu)], delay: .milliseconds(300))
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.showSpokenLanguage()
        coordinator.requestCancel()
        await coordinator.settle()

        #expect(coordinator.attention == .reviewTranslation)
        #expect(coordinator.reviewText == english)
        #expect(coordinator.attentionActions.contains(.retry), "the recording is still kept")
    }

    @Test func theSpokenLanguageTextOffersNoToneButTheTranslationDoes() async {
        defer { cleanUp() }
        processor.script([held(.reviewTranslation, english), held(.reviewText, telugu)])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        #expect(coordinator.canChangeReviewTone)

        coordinator.showSpokenLanguage()
        await coordinator.settle()
        #expect(!coordinator.canChangeReviewTone)

        coordinator.showEnglishTranslation()
        await coordinator.settle()
        #expect(coordinator.canChangeReviewTone)
    }

    @Test func aToneChosenForTheTranslationComesBackWithIt() async {
        defer { cleanUp() }
        let casual = StyleOptions(tone: .casual)
        processor.script([
            held(.reviewTranslation, english),
            .review(
                DictationReview(
                    text: "Hey, send me the file tomorrow", original: english, language: "en", style: casual),
                engine: .cloud),
            held(.reviewText, telugu),
        ])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        coordinator.changeReviewTone(.casual)
        await coordinator.settle()

        coordinator.showSpokenLanguage()
        await coordinator.settle()
        coordinator.showEnglishTranslation()
        await coordinator.settle()

        #expect(coordinator.reviewText == "Hey, send me the file tomorrow")
        #expect(coordinator.reviewTone == .casual)
        #expect(coordinator.reviewOriginal == english)
    }

    @Test func aDetectedLanguageHasNoNameAndADictationOffersNoSwitch() async {
        defer { cleanUp() }
        processor.script([held(.reviewTranslation, english)])
        let coordinator = makeCoordinator(language: SpokenLanguages.automatic)
        await speak(coordinator)
        #expect(coordinator.reviewSpokenLanguage == nil)
        #expect(coordinator.canShowSpokenLanguage)
        coordinator.dismiss()

        processor.script([held(.reviewText, "send it")])
        let plain = makeCoordinator(language: "en-US")
        await speak(plain)
        #expect(!plain.canShowSpokenLanguage && !plain.canShowEnglishTranslation)
    }
}
