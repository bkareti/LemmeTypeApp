import Domain
import Foundation

/// A review in one language: what is shown, the first result, and its tone (E12-S6).
struct ReviewLanguageState {
    var snapshot: ReviewSnapshot
    let first: ReviewSnapshot?
    let tone: Tone?
}

/// The translation and the text in the spoken language, once each has been shown, so
/// switching back needs no new upload (E12-S6). In memory only; never logged.
struct ReviewLanguages {
    var translation: ReviewLanguageState?
    var spoken: ReviewLanguageState?
    var showsSpoken = false
    /// Why the last attempt to get the spoken-language text failed.
    var failure: DictationIssue?
}

/// Showing a translation's recording in the language that was spoken (E12-S6): the same
/// recording is recognised again with output *original*, for example Telugu with English
/// words kept in English (Sarvam `codemix` behind the gateway).
extension RecordingCoordinator {
    /// The spoken language of the translation under review, or `nil` when it was detected.
    public var reviewSpokenLanguage: String? {
        guard let language = session?.language, !SpokenLanguages.isAutomatic(language) else { return nil }
        return language
    }

    /// A translation is under review and its spoken-language text can be shown: already
    /// fetched, or the recording is still kept (Translate Again is offered).
    public var canShowSpokenLanguage: Bool {
        guard attention == .reviewTranslation, reviewChange == nil, session?.purpose == .dictation else { return false }
        return reviewLanguages.spoken != nil || attentionActions.contains(.retry)
    }

    /// Showing the spoken-language text sends the recording to the cloud again.
    public var spokenLanguageNeedsUpload: Bool {
        reviewLanguages.spoken == nil && session?.engine?.isCloud == true
    }

    /// The spoken-language text is shown and the translation is one tap away.
    public var canShowEnglishTranslation: Bool {
        reviewLanguages.showsSpoken && reviewLanguages.translation != nil && reviewChange == nil
    }

    /// Why the spoken-language text could not be fetched, while the translation is shown again.
    public var spokenLanguageFailure: DictationIssue? { reviewLanguages.failure }

    public func showSpokenLanguage() {
        enqueue { $0.switchToSpokenLanguage() }
    }

    public func showEnglishTranslation() {
        enqueue { $0.switchToEnglishTranslation() }
    }

    func forgetReviewLanguages() {
        reviewLanguages = ReviewLanguages()
    }

    private func currentLanguageState() -> ReviewLanguageState? {
        guard let attention else { return nil }
        return ReviewLanguageState(
            snapshot: ReviewSnapshot(
                issue: attention, transcript: pendingTranscript, review: pendingReview, actions: attentionActions),
            first: reviewFirst, tone: reviewTone)
    }

    private func restore(_ state: ReviewLanguageState, output: SpeechOutput) {
        session?.speechOutput = output
        show(state.snapshot)
        reviewFirst = state.first
        reviewTone = state.tone
    }

    private func switchToSpokenLanguage() {
        guard canShowSpokenLanguage, var next = session, let translation = currentLanguageState() else { return }
        reviewLanguages.failure = nil
        reviewLanguages.translation = translation
        if let spoken = reviewLanguages.spoken {
            reviewLanguages.showsSpoken = true
            restore(spoken, output: .original)
            return
        }
        guard machine.handle(.retry) else { return }
        reviewChange = .spokenLanguage(translation: translation)
        beginRetry()
        next.speechOutput = .original
        session = next
        startProcessing(next)
    }

    private func switchToEnglishTranslation() {
        guard canShowEnglishTranslation, let english = reviewLanguages.translation else { return }
        reviewLanguages.spoken = currentLanguageState()
        reviewLanguages.showsSpoken = false
        restore(english, output: .english)
    }

    /// Ends the recognition in the spoken language: shows its text, or the translation again
    /// with the reason when it failed or was cancelled.
    func finishSpokenLanguage(_ outcome: DictationOutcome, translation: ReviewLanguageState) {
        let shown: ReviewSnapshot
        switch outcome {
        case .needsAttention(let issue, _, _, let transcript?) where issue.isReviewOfText:
            shown = ReviewSnapshot(
                issue: issue, transcript: transcript, review: nil,
                actions: issue.actions(alternatives: []).filter(isOffered))
        case .review(let review, _):
            let issue = DictationIssue.reviewRewrite(review.notice)
            shown = ReviewSnapshot(
                issue: issue, transcript: review.text, review: review,
                actions: issue.actions(alternatives: []).filter(isOffered))
        default:
            if case .needsAttention(let issue, _, _, _) = outcome { reviewLanguages.failure = issue }
            reviewLanguages.translation = nil
            restore(translation, output: .english)
            finishSession(displayFor: attentionDisplay)
            return
        }
        // The recording is deleted once the spoken-language text is in, so the
        // translation can no longer be made again.
        var english = translation
        english.snapshot = translation.snapshot.withoutRecordingActions()
        reviewLanguages.translation = english
        reviewLanguages.showsSpoken = true
        show(shown)
        reviewFirst = shown
        reviewTone = session?.dictationMode.effectiveStyle.tone
        feedback.announce(
            String(localized: "Dictation needs your attention. \(shown.issue.userMessage)", bundle: .module))
        finishSession(displayFor: attentionDisplay)
    }
}

extension ReviewSnapshot {
    /// The same review without the choices that need the recording.
    func withoutRecordingActions() -> ReviewSnapshot {
        ReviewSnapshot(
            issue: issue, transcript: transcript, review: review,
            actions: actions.filter { action in
                switch action {
                case .retry, .useEngine, .useLanguage, .saveAudio: false
                default: true
                }
            })
    }
}
