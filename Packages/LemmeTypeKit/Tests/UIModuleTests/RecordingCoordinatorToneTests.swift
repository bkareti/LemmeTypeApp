import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E12-S5: choosing Neutral, Casual, or Professional for English text on the review screen.
@MainActor
struct RecordingCoordinatorToneTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let processor = RecordingSpy()
    private let copier = FakeTextDelivery()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-CoordinatorTone-\(UUID().uuidString)", isDirectory: true))
    private let casual = StyleOptions(tone: .casual)

    private func makeCoordinator(language: String = "en-US") -> RecordingCoordinator {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage,
                permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: feedback, preferences: FakePreferences(dictationLanguage: language),
            textCopier: copier, finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }

    private func speak(_ coordinator: RecordingCoordinator) async {
        coordinator.handle(.start(nil))
        await coordinator.settle()
        source.emitTone(seconds: 0.5)
        coordinator.handle(.stop)
        await coordinator.settle()
    }

    private func held(_ issue: DictationIssue, _ text: String = "can you send it") -> DictationOutcome {
        .needsAttention(issue, engine: .cloud, alternatives: [], transcript: text)
    }

    private func toned(
        _ text: String, style: StyleOptions, original: String = "can you send it", notice: RewriteNotice? = nil
    ) -> DictationOutcome {
        .review(
            DictationReview(
                text: notice == nil ? text : original, original: original, language: "en", style: style,
                notice: notice), engine: .cloud)
    }

    @Test func anEnglishReviewOffersToneAndStartsAtTheModesTone() async {
        defer { cleanUp() }
        processor.script([held(.reviewText)])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        #expect(coordinator.canChangeReviewTone)
        #expect(coordinator.reviewTone == .neutral)
        #expect(RecordingCoordinator.reviewToneChoices == [.neutral, .casual, .professional])
    }

    @Test func casualRewritesTheWordsBeforeAnyRewriteAndKeepsTheReview() async {
        defer { cleanUp() }
        processor.script([held(.reviewText), toned("hey, can you send it?", style: casual)])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.changeReviewTone(.casual)
        await coordinator.settle()

        #expect(processor.restylings == [.init(text: "can you send it", style: casual, language: "en-US")])
        #expect(processor.consumed.count == 1, "the audio is not recognised again")
        #expect(coordinator.attention == .reviewText)
        #expect(coordinator.reviewText == "hey, can you send it?")
        #expect(coordinator.reviewOriginal == "can you send it")
        #expect(coordinator.reviewTone == .casual)
        #expect(copier.copied.isEmpty, "nothing is copied by a tone change")
    }

    @Test func aTranslationStaysATranslationWithTranslateAgain() async {
        defer { cleanUp() }
        let professional = StyleOptions(tone: .professional)
        processor.script([
            held(.reviewTranslation, "Send me the file"),
            toned("Could you please send me the file?", style: professional, original: "Send me the file"),
        ])
        let coordinator = makeCoordinator(language: "te")
        await speak(coordinator)
        let choices = coordinator.attentionActions
        #expect(coordinator.canChangeReviewTone, "the translation is English")

        coordinator.changeReviewTone(.professional)
        await coordinator.settle()

        #expect(processor.restylings.first?.language == "en")
        #expect(coordinator.attention == .reviewTranslation)
        #expect(coordinator.attentionActions == choices)
        #expect(coordinator.attentionActions.contains(.retry))
        #expect(coordinator.reviewText == "Could you please send me the file?")
    }

    @Test func choosingTheFirstToneAgainShowsTheFirstResultWithoutTheModel() async {
        defer { cleanUp() }
        processor.script([held(.reviewText), toned("hey, can you send it?", style: casual)])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        coordinator.changeReviewTone(.casual)
        await coordinator.settle()

        coordinator.changeReviewTone(.neutral)
        await coordinator.settle()

        #expect(processor.restylings.count == 1)
        #expect(coordinator.reviewText == "can you send it")
        #expect(coordinator.reviewOriginal == nil)
        #expect(coordinator.reviewTone == .neutral)
        #expect(coordinator.attention == .reviewText)
    }

    @Test func toneIsNotOfferedForTextThatIsNotEnglish() async {
        defer { cleanUp() }
        processor.script([held(.reviewText, "నేను file పంపుతాను")])
        let coordinator = makeCoordinator(language: "te")
        await speak(coordinator)

        #expect(!coordinator.canChangeReviewTone)
        coordinator.changeReviewTone(.casual)
        await coordinator.settle()
        #expect(processor.restylings.isEmpty)
        #expect(coordinator.reviewText == "నేను file పంపుతాను")
    }

    @Test func aRejectedRewriteKeepsTheWordsWithANotice() async {
        defer { cleanUp() }
        processor.script([
            held(.reviewText), toned("", style: casual, notice: .meaningChanged([.numberChanged])),
        ])
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.changeReviewTone(.casual)
        await coordinator.settle()

        #expect(coordinator.reviewText == "can you send it")
        #expect(coordinator.reviewNotice == .meaningChanged([.numberChanged]))
        #expect(coordinator.reviewOriginal == nil, "nothing to compare when no rewrite applied")
    }

    @Test func copyCopiesTheTextOnScreenAfterAToneChange() async {
        defer { cleanUp() }
        processor.script([held(.reviewText), toned("hey, can you send it?", style: casual)])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        coordinator.changeReviewTone(.casual)
        await coordinator.settle()

        coordinator.perform(.copyText)
        await coordinator.settle()

        #expect(copier.copied == ["hey, can you send it?"])
        #expect(coordinator.state == .completed)
    }

    @Test func cancelWhileRewritingGoesBackToTheReview() async {
        defer { cleanUp() }
        processor.script([held(.reviewText), toned("hey", style: casual)], delay: .milliseconds(300))
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.changeReviewTone(.casual)
        coordinator.requestCancel()
        await coordinator.settle()

        #expect(coordinator.attention == .reviewText)
        #expect(coordinator.reviewText == "can you send it")
        #expect(coordinator.reviewTone == .neutral)
    }

    @Test func aFailedRewriteGoesBackToTheReview() async {
        defer { cleanUp() }
        processor.script([held(.reviewText)])  // nothing scripted for the rewrite: it ends cancelled
        let coordinator = makeCoordinator()
        await speak(coordinator)

        coordinator.changeReviewTone(.professional)
        await coordinator.settle()

        #expect(coordinator.attention == .reviewText)
        #expect(coordinator.reviewText == "can you send it")
        #expect(coordinator.reviewTone == .neutral)
    }

    @Test func regenerateKeepsTheChosenTone() async {
        defer { cleanUp() }
        let professional = StyleOptions(tone: .professional)
        processor.script([
            toned("Please send it.", style: .none, original: "can you send it"),
            toned("Could you send it?", style: professional),
            toned("Would you send it?", style: professional),
        ])
        let coordinator = makeCoordinator()
        await speak(coordinator)
        coordinator.changeReviewTone(.professional)
        await coordinator.settle()

        coordinator.perform(.regenerate)
        await coordinator.settle()

        #expect(processor.regenerations.isEmpty)
        #expect(processor.restylings.map(\.style) == [professional, professional])
        #expect(coordinator.reviewText == "Would you send it?")
        #expect(coordinator.reviewTone == .professional)
    }
}
