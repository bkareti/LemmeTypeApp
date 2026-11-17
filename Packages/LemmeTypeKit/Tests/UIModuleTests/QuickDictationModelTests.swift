import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E8-S6, E8-S7: the Quick Dictation screen over the shared recorder.
@MainActor
struct QuickDictationModelTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let processor = RecordingSpy()
    private let copier = FakeTextDelivery()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-QuickDictation-\(UUID().uuidString)", isDirectory: true))

    private func makeModel(
        microphone: PermissionStatus = .granted,
        inbox: LaunchRequestInbox? = nil,
        lifetime: CopiedTextLifetime = .twoMinutes,
        speech: FakeSpeechAuthorizer? = nil,
        rewriter: RewriterAvailability = .unavailable,
        language: String = "en-US"
    ) -> QuickDictationModel {
        let recorder = RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: microphone])),
            processor: processor, feedback: feedback, preferences: FakePreferences(dictationLanguage: language),
            textCopier: copier, finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
        return QuickDictationModel(
            recorder: recorder, feedback: feedback, microphoneStatus: { microphone },
            requestMicrophone: { .granted }, openSettings: {}, lifetime: { lifetime },
            needsSpeechRecognition: { speech?.status() == .notRequested },
            requestSpeechRecognition: { _ = await speech?.requestAuthorization() },
            launchRequests: inbox, rewriterAvailability: { _ in rewriter })
    }

    private func review(_ text: String) -> DictationOutcome {
        .needsAttention(.reviewText, engine: .whisper, alternatives: [], transcript: text)
    }

    private func dictate(_ model: QuickDictationModel) async {
        model.start()
        await model.recorder.settle()
        source.emitTone(seconds: 0.3)
        model.stop()
        await model.recorder.settle()
    }

    @Test func aFinishedDictationIsShownForReviewAndNothingIsCopiedYet() async {
        processor.script([review("Ship it Friday")])
        let model = makeModel()

        await dictate(model)

        #expect(model.screen == .review(text: "Ship it Friday"))
        #expect(copier.copied.isEmpty)
        #expect(model.copiedFor == nil)
        model.discard()  // the fake processor keeps the audio until a decision, unlike the real pipeline
        await model.recorder.settle()
    }

    @Test func copyPutsExactlyTheReviewedTextOnTheClipboardOnceAndConfirms() async {
        processor.script([review("Ship it Friday")])
        let model = makeModel(lifetime: .tenMinutes)
        await dictate(model)

        await model.copy()

        #expect(copier.copied == ["Ship it Friday"])
        #expect(model.copiedFor == .tenMinutes)
        #expect(feedback.announcements.contains(QuickDictationModel.copiedMessage(for: .tenMinutes)))
        #expect(feedback.sounds.last == .copied)
    }

    @Test func discardCopiesNothingAndReturnsToReady() async throws {
        processor.script([review("Private words")])
        let model = makeModel()
        await dictate(model)

        model.discard()
        await model.recorder.settle()

        #expect(copier.copied.isEmpty)
        #expect(model.screen == .ready)
    }

    @Test func dictatingAgainDropsTheResultAndRecordsAgain() async {
        processor.script([review("First try")])
        let model = makeModel()
        await dictate(model)

        model.dictateAgain()
        await model.recorder.settle()

        #expect(model.screen == .recording)
        #expect(copier.copied.isEmpty)
        model.cancel()
        await model.recorder.settle()
    }

    @Test func theFirstStartExplainsTheMicrophoneBeforeAskingTheSystem() async {
        let model = makeModel(microphone: .notRequested)

        model.start()
        await model.recorder.settle()

        #expect(model.isExplainingMicrophone)
        #expect(model.screen == .ready)
        #expect(!source.isRunning)

        model.cancelExplanation()
        #expect(!model.isExplainingMicrophone)
        #expect(model.screen == .ready)
    }

    /// App Review: the first dictation must work without a detour to Settings, so Speech
    /// Recognition is asked for right after the microphone when nothing else is ready.
    @Test func theFirstStartAsksForSpeechRecognitionAfterTheExplanationWhenNeeded() async {
        let speech = FakeSpeechAuthorizer(status: .notRequested, answer: .granted)
        let model = makeModel(microphone: .granted, speech: speech)

        model.start()
        await model.recorder.settle()
        #expect(model.isExplainingMicrophone, "explained first, even with the microphone already allowed")
        #expect(speech.requestCount == 0)

        await model.continueAfterExplanation()
        await model.recorder.settle()
        #expect(speech.requestCount == 1)
        #expect(model.screen == .recording)
        model.cancel()
        await model.recorder.settle()
    }

    @Test func aDecidedSpeechPermissionIsNotAskedAgain() async {
        let speech = FakeSpeechAuthorizer(status: .denied)
        let model = makeModel(microphone: .granted, speech: speech)

        model.start()
        await model.recorder.settle()

        #expect(!model.isExplainingMicrophone)
        #expect(speech.requestCount == 0)
        model.cancel()
        await model.recorder.settle()
    }

    @Test func deniedMicrophoneNeverRecordsAndOffersSettings() async {
        let model = makeModel(microphone: .denied)

        model.start()
        await model.recorder.settle()

        #expect(model.screen == .failed(.microphonePermissionMissing))
        #expect(!source.isRunning)
    }

    @Test func denyingAtTheSystemPromptSaysWhyAndOffersSettings() async {
        let permissions = FakePermissions(statuses: [.microphone: .notRequested], microphoneAnswer: .denied)
        let recorder = RecordingCoordinator(
            capture: AudioCaptureService(source: source, storage: storage, permissions: permissions),
            processor: processor, feedback: feedback, preferences: FakePreferences(), textCopier: copier,
            finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
        let model = QuickDictationModel(
            recorder: recorder, feedback: feedback, microphoneStatus: { permissions.status(for: .microphone) },
            requestMicrophone: { await permissions.requestMicrophoneAccess() }, openSettings: {})

        model.start()
        #expect(model.isExplainingMicrophone)
        await model.continueAfterExplanation()
        await model.recorder.settle()

        #expect(permissions.microphoneRequestCount == 1)
        #expect(model.screen == .failed(.microphonePermissionMissing))
        #expect(source.startCount == 0)
    }

    @Test func allowingAtTheSystemPromptStartsRecording() async {
        let permissions = FakePermissions(statuses: [.microphone: .notRequested], microphoneAnswer: .granted)
        let recorder = RecordingCoordinator(
            capture: AudioCaptureService(source: source, storage: storage, permissions: permissions),
            processor: processor, feedback: feedback, preferences: FakePreferences(), textCopier: copier,
            finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
        let model = QuickDictationModel(
            recorder: recorder, feedback: feedback, microphoneStatus: { permissions.status(for: .microphone) },
            requestMicrophone: { await permissions.requestMicrophoneAccess() }, openSettings: {})

        model.start()
        await model.continueAfterExplanation()
        await model.recorder.settle()

        #expect(model.screen == .recording)
        model.cancel()
        await model.recorder.settle()
    }

    @Test func aShortcutRequestStartsOnceAndAnExpiredOneStartsNothing() async {
        let now = TestNow()
        let inbox = LaunchRequestInbox(lifetime: 10, now: { now.date })
        let model = makeModel(inbox: inbox)

        inbox.post()
        model.startIfRequestedByShortcut()
        await model.recorder.settle()
        #expect(model.screen == .recording)
        model.cancel()
        await model.recorder.settle()

        model.startIfRequestedByShortcut()  // already used
        await model.recorder.settle()
        #expect(model.screen == .ready)

        inbox.post()
        now.advance(by: 60)
        model.startIfRequestedByShortcut()  // expired
        await model.recorder.settle()
        #expect(model.screen == .ready)
        #expect(!source.isRunning)
    }

    @Test func aShortcutRequestWithoutMicrophoneAccessExplainsInsteadOfRecording() async {
        let inbox = LaunchRequestInbox()
        let model = makeModel(microphone: .notRequested, inbox: inbox)

        inbox.post()
        model.startIfRequestedByShortcut()
        await model.recorder.settle()

        #expect(model.isExplainingMicrophone)
        #expect(!source.isRunning)
    }

    @Test func aCancelledOrFailedDictationNeverTouchesTheClipboard() async {
        let model = makeModel()
        model.start()
        await model.recorder.settle()
        model.cancel()
        await model.recorder.settle()

        #expect(copier.copied.isEmpty)
        #expect(model.screen == .ready)
    }

    // MARK: Spoken language (E12-S6)

    @Test func aTranslationOffersItsSpokenLanguageByNameAndBack() async {
        processor.script([
            .needsAttention(.reviewTranslation, engine: .cloud, alternatives: [], transcript: "Send it tomorrow"),
            .needsAttention(.reviewText, engine: .cloud, alternatives: [], transcript: "రేపు send చేయి"),
        ])
        let model = makeModel(language: "te")
        await dictate(model)

        #expect(model.canShowSpokenLanguage && model.spokenLanguageNeedsUpload)
        #expect(model.showSpokenLanguageTitle.hasPrefix("Show in Telugu"))

        model.showSpokenLanguage()
        await model.recorder.settle()
        #expect(model.screen == .review(text: "రేపు send చేయి"))
        #expect(model.canShowEnglish && !model.canChangeTone)

        model.showEnglish()
        await model.recorder.settle()
        #expect(model.screen == .review(text: "Send it tomorrow"))
        #expect(model.spokenLanguageFailureMessage == nil)
        model.discard()
        await model.recorder.settle()
    }

    // MARK: Tone (E12-S5)

    @Test func theToneRowIsOfferedForEnglishAndWorksWhenTheModelIsReady() async {
        processor.script([
            review("can you send it"),
            .review(
                DictationReview(
                    text: "hey, can you send it?", original: "can you send it", language: "en",
                    style: StyleOptions(tone: .casual)), engine: .whisper),
        ])
        let model = makeModel(rewriter: .ready)
        await dictate(model)
        await model.refreshToneAvailability()

        #expect(model.canChangeTone && model.isToneReady)
        #expect(model.toneUnavailableMessage == nil)
        #expect(model.selectedTone == .neutral)
        #expect(model.toneChoices == [.neutral, .casual, .professional])

        model.chooseTone(.casual)
        await model.recorder.settle()

        #expect(model.screen == .review(text: "hey, can you send it?"))
        #expect(model.selectedTone == .casual)
        #expect(model.canCompareWithOriginal)
        model.discard()
        await model.recorder.settle()
    }

    @Test func withoutAppleIntelligenceTheToneRowIsDisabledAndSaysWhy() async {
        processor.script([review("can you send it")])
        let model = makeModel(rewriter: .notEnabled)
        await dictate(model)
        await model.refreshToneAvailability()

        #expect(model.canChangeTone && !model.isToneReady)
        #expect(model.toneUnavailableMessage?.contains("Apple Intelligence is turned off") == true)

        model.chooseTone(.professional)
        await model.recorder.settle()
        #expect(processor.restylings.isEmpty)
        #expect(model.screen == .review(text: "can you send it"))
        model.discard()
        await model.recorder.settle()
    }
}

/// E8-S6: a translation or a rewrite is reviewed like any dictation, and offers Copy, not Insert.
@MainActor
struct QuickDictationReviewKindTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let processor = RecordingSpy()
    private let copier = FakeTextDelivery()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-QuickReview-\(UUID().uuidString)", isDirectory: true))

    private func review(
        _ outcome: DictationOutcome
    ) async -> QuickDictationModel {
        processor.script([outcome])
        let recorder = RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: feedback, preferences: FakePreferences(), textCopier: copier,
            finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
        let model = QuickDictationModel(
            recorder: recorder, feedback: feedback, microphoneStatus: { .granted },
            requestMicrophone: { .granted }, openSettings: {})
        model.start()
        await recorder.settle()
        source.emitTone(seconds: 0.3)
        model.stop()
        await recorder.settle()
        return model
    }

    @Test func aTranslationIsReviewedAndOffersTranslateAgainButNotInsert() async {
        let model = await review(
            .needsAttention(.reviewTranslation, engine: .whisper, alternatives: [], transcript: "see you at three"))

        #expect(model.screen == .review(text: "see you at three"))
        #expect(model.reviewKind == .translation)
        #expect(model.reviewRetryAction == .retry)
        #expect(!model.recorder.attentionActions.isEmpty)
        #expect(!model.canCompareWithOriginal)
        model.discard()
        await model.recorder.settle()
    }

    @Test func aRewriteCanBeComparedWithTheOriginalAndCopyCopiesWhatIsShown() async {
        let rewrite = DictationReview(
            text: "Could we meet at three?", original: "meet at three", language: "en",
            style: StyleOptions(tone: .professional, format: .plainText, length: .original))
        let model = await review(.review(rewrite, engine: .whisper))

        #expect(model.screen == .review(text: "Could we meet at three?"))
        #expect(model.reviewKind == .rewrite)
        #expect(model.canCompareWithOriginal)
        #expect(model.reviewRetryAction == .regenerate)

        model.toggleOriginal()
        #expect(model.screen == .review(text: "meet at three"))
        #expect(model.showsOriginal)

        await model.copy()
        #expect(copier.copied == ["meet at three"])
    }
}
