import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E9-S3 and E9-S5: refusing before recording, choosing a language after
/// uncertain detection, and reviewing a translation.
@MainActor
struct RecordingCoordinatorLanguageTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let processor = RecordingSpy()
    private let copier = FakeTextDelivery()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-CoordinatorLanguage-\(UUID().uuidString)", isDirectory: true))

    private func makeCoordinator(preferences: FakePreferences = FakePreferences()) -> RecordingCoordinator {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage,
                permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: feedback, preferences: preferences, textCopier: copier,
            finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
    }

    /// Recordings kept for a decision must not outlive the test (`make privacy-check`).
    private func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }

    private var leftoverFiles: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
    }

    private func speak(_ coordinator: RecordingCoordinator) async {
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        source.emitTone(seconds: 0.5)
        coordinator.handle(.stop)
        await coordinator.settle()
    }

    private let review = DictationOutcome.needsAttention(
        .reviewTranslation, engine: .whisper, alternatives: [], transcript: "Ship it on Wednesday.")

    // MARK: Refused before recording (E9-S3)

    @Test func anUnavailableLanguageIsRefusedBeforeTheMicrophoneStarts() async {
        defer { cleanUp() }
        processor.refuseLanguage(with: .languageUnavailable(.needsModel(.whisperSmall)))
        let coordinator = makeCoordinator(preferences: FakePreferences(dictationLanguage: "hi"))
        var opened: [SettingsNavigation.Pane] = []
        coordinator.onOpenSettings = { opened.append($0) }

        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()

        #expect(coordinator.attention == .languageUnavailable(.needsModel(.whisperSmall)))
        #expect(coordinator.attentionActions == [.chooseLanguage, .discard])
        #expect(!source.isRunning, "the microphone must not start")
        #expect(processor.consumed.isEmpty)
        #expect(feedback.announcements.last?.hasPrefix("Dictation can’t start.") == true)
        #expect(leftoverFiles.isEmpty)

        coordinator.perform(.chooseLanguage)
        await coordinator.settle()
        #expect(opened == [.dictation])
    }

    @Test func theSessionCapturesLanguageAndOutputFromSettings() async {
        defer { cleanUp() }
        let preferences = FakePreferences(dictationLanguage: "te")
        preferences.speechOutput = .english
        let coordinator = makeCoordinator(preferences: preferences)
        await speak(coordinator)
        #expect(processor.languages == ["te"])
        #expect(processor.outputs == [.english])

        // Changing Settings later affects only the next session.
        preferences.dictationLanguage = "hi"
        preferences.speechOutput = .original
        await speak(coordinator)
        #expect(processor.languages == ["te", "hi"])
        #expect(processor.outputs == [.english, .original])
    }

    @Test func aModeCanOverrideLanguageAndOutput() async throws {
        defer { cleanUp() }
        let mode = DictationMode(name: "Hindi to English", language: "hi", speechOutput: .english)
        var library = PersonalizationLibrary.empty
        try library.upsert(mode)
        let preferences = FakePreferences()
        preferences.dictationMode = mode.id
        let coordinator = RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage,
                permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: feedback, preferences: preferences,
            finishedDisplay: .milliseconds(50), personalization: { library })
        await speak(coordinator)
        #expect(processor.languages == ["hi"])
        #expect(processor.outputs == [.english])
    }

    // MARK: Choosing a language (E9-S2)

    @Test func choosingALanguageProcessesTheSameRecordingAgain() async {
        defer { cleanUp() }
        processor.script([
            .needsAttention(.recognitionFailed(.languageUncertain), engine: .whisper, alternatives: [], transcript: nil)
        ])
        let coordinator = makeCoordinator(preferences: FakePreferences(dictationLanguage: SpokenLanguages.automatic))
        await speak(coordinator)
        #expect(coordinator.attentionActions == [.useLanguage("en"), .useLanguage("hi"), .useLanguage("te"), .discard])
        let kept = processor.consumed[0]

        coordinator.perform(.useLanguage("te"))
        await coordinator.settle()

        #expect(processor.languages == [SpokenLanguages.automatic, "te"])
        #expect(processor.consumed[1].fileURL == kept.fileURL, "the same recording is used again")
        #expect(coordinator.state == .completed)
    }

    // MARK: Reviewing a translation (E9-S5)

    @Test func aTranslationIsShownAndNothingIsDelivered() async {
        defer { cleanUp() }
        processor.script([review])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        #expect(coordinator.attention == .reviewTranslation)
        #expect(coordinator.reviewText == "Ship it on Wednesday.")
        #expect(coordinator.attentionActions == [.insertText, .copyText, .retry, .discard])
        #expect(processor.deliveries.isEmpty)
        #expect(copier.copied.isEmpty)
    }

    @Test func insertDeliversTheReviewedTextOnceAndEndsTheSession() async {
        defer { cleanUp() }
        processor.script([review])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.perform(.insertText)
        await coordinator.settle()

        #expect(processor.deliveries == ["Ship it on Wednesday."])
        #expect(coordinator.state == .completed)
        #expect(coordinator.reviewText == nil)
        #expect(leftoverFiles.isEmpty)
    }

    @Test func copyPutsTheTranslationOnTheClipboardAndNeverInsertsIt() async {
        defer { cleanUp() }
        processor.script([review])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.perform(.copyText)
        await coordinator.settle()

        #expect(copier.copied == ["Ship it on Wednesday."])
        #expect(processor.deliveries.isEmpty)
        #expect(coordinator.state == .completed)
        #expect(coordinator.reviewText == nil)
    }

    @Test func translateAgainRunsTheSameRecordingAndReplacesTheText() async {
        defer { cleanUp() }
        processor.script([
            review,
            .needsAttention(.reviewTranslation, engine: .whisper, alternatives: [], transcript: "Ship it Wednesday."),
        ])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        coordinator.perform(.retry)
        await coordinator.settle()

        #expect(processor.consumed.count == 2)
        #expect(processor.consumed[0].fileURL == processor.consumed[1].fileURL)
        #expect(coordinator.reviewText == "Ship it Wednesday.")
    }

    @Test func discardDeletesTheRecordingAndTheText() async {
        defer { cleanUp() }
        processor.script([review])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        #expect(!leftoverFiles.isEmpty, "the recording is kept while the translation is reviewed")

        coordinator.perform(.discard)
        await coordinator.settle()

        #expect(coordinator.reviewText == nil)
        #expect(coordinator.state == .idle)
        #expect(leftoverFiles.isEmpty)
        #expect(processor.deliveries.isEmpty)
    }

    @Test func aNewSessionReplacesAReviewAndDeletesItsRecording() async {
        defer { cleanUp() }
        processor.script([review])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()

        #expect(coordinator.reviewText == nil)
        #expect(leftoverFiles.count == 1, "only the new recording exists")
    }

    @Test func reviewingAnnouncesTheStateForVoiceOver() async {
        defer { cleanUp() }
        processor.script([review])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        #expect(feedback.announcements.last?.contains("Read the translation") == true)
    }
}
