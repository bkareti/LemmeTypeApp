import Domain
import Foundation

/// One state of a review: the text shown and the choices for it (E12-S5). In memory
/// only; never logged.
struct ReviewSnapshot {
    let issue: DictationIssue
    let transcript: String?
    let review: DictationReview?
    let actions: [DictationAction]

    /// The words before any rewrite: what a newly chosen tone is applied to.
    var wordsBeforeRewrite: String? { review?.original ?? transcript }
}

/// A change to the review that is being processed, and what to show again if it does
/// not finish (E12-S5).
enum ReviewChange {
    /// `replacesFirst`: a Regenerate in the mode's own style, whose result becomes the first one.
    case tone(previous: ReviewSnapshot, previousTone: Tone?, replacesFirst: Bool)
    /// The same recording, recognised again in the language that was spoken (E12-S6).
    case spokenLanguage(translation: ReviewLanguageState)
}

extension DictationIssue {
    /// A finished result waiting to be read, rather than a problem.
    var isReviewOfText: Bool {
        switch self {
        case .reviewText, .reviewTranslation, .reviewRewrite: true
        default: false
        }
    }

    var isRewriteReview: Bool {
        if case .reviewRewrite = self { return true }
        return false
    }
}

/// Changing the review after the result is in (E12-S5): another tone for English text,
/// rewritten on the device from the words before any rewrite.
extension RecordingCoordinator {
    /// The text from before the rewrite, while a rewrite is reviewed (E10-S4).
    public var reviewOriginal: String? {
        guard attention?.isReviewOfText == true, pendingReview?.isRewritten == true else { return nil }
        return pendingReview?.original
    }

    /// Switches the review between the rewrite and the text it came from.
    public func toggleReviewOriginal() {
        guard reviewOriginal != nil else { return }
        reviewShowsOriginal.toggle()
    }

    /// The tone, format, and length of the rewrite under review (E10-S4).
    public var reviewStyle: StyleOptions? {
        attention?.isReviewOfText == true ? pendingReview?.style : nil
    }

    /// A new result arrived: nothing from an earlier rewrite belongs to it.
    func forgetRewriteIfNewResult(_ issue: DictationIssue) {
        guard issue.isReviewOfText else { return }
        pendingReview = nil
        reviewShowsOriginal = false
    }

    /// The tones offered on the review screen, in order.
    public static let reviewToneChoices: [Tone] = [.neutral, .casual, .professional]

    /// The language of the text under review: English after a translation.
    public var reviewLanguage: String? {
        guard let attention, attention.isReviewOfText, let session else { return nil }
        if let pendingReview { return pendingReview.language }
        if attention == .reviewTranslation || session.speechOutput == .english {
            return SpokenLanguages.english.code
        }
        return session.language
    }

    /// Why the text under review is not the rewrite that was asked for, if it isn't.
    public var reviewNotice: RewriteNotice? {
        attention?.isReviewOfText == true ? pendingReview?.notice : nil
    }

    /// Whether another tone can be chosen: only for English text (Apple's on-device
    /// model does not support Telugu, and text never goes to the cloud).
    public var canChangeReviewTone: Bool {
        guard reviewFirst != nil, session?.purpose == .dictation, let reviewLanguage else { return false }
        return SpokenLanguages.isEnglish(reviewLanguage)
    }

    /// Shows the reviewed text in `tone`. The mode's own tone shows the first result
    /// again without the model; any other tone is rewritten on the device.
    public func changeReviewTone(_ tone: Tone) {
        enqueue { $0.applyReviewTone(tone) }
    }

    /// Called whenever processing ends in a review; only the first result is kept.
    func rememberFirstReview() {
        guard reviewFirst == nil, let attention, attention.isReviewOfText else { return }
        reviewFirst = snapshotOfReview(attention)
        reviewTone = session?.dictationMode.effectiveStyle.tone
    }

    func forgetReviewHistory() {
        reviewFirst = nil
        reviewChange = nil
        reviewTone = nil
        forgetReviewLanguages()
    }

    private func snapshotOfReview(_ issue: DictationIssue) -> ReviewSnapshot {
        ReviewSnapshot(issue: issue, transcript: pendingTranscript, review: pendingReview, actions: attentionActions)
    }

    private func applyReviewTone(_ tone: Tone) {
        guard canChangeReviewTone, tone != reviewTone, let first = reviewFirst, let session, let attention,
            let words = first.wordsBeforeRewrite, let language = reviewLanguage
        else { return }
        let modeStyle = session.dictationMode.effectiveStyle
        var style = modeStyle
        style.tone = tone
        let previous = snapshotOfReview(attention)
        let previousTone = reviewTone
        reviewTone = tone
        if style == modeStyle {
            show(first)
            return
        }
        if style.isNone {
            // The mode's tone was its only change: the words before the rewrite are the text.
            let issue = first.issue.isRewriteReview ? DictationIssue.reviewText : first.issue
            show(ReviewSnapshot(issue: issue, transcript: words, review: nil, actions: actions(for: issue, previous)))
            return
        }
        guard machine.handle(.retry) else {
            reviewTone = previousTone
            return
        }
        reviewChange = .tone(previous: previous, previousTone: previousTone, replacesFirst: false)
        beginRetry()
        let chosen = style
        run(session) { processor, updates in
            await processor.restyle(words, style: chosen, language: language, for: session) { updates.yield($0) }
        }
    }

    /// Rewrites the reviewed text again (Regenerate, E10-S4): in the mode's style, or
    /// in the tone the user chose on the review screen (E12-S5).
    func regenerateReview(for session: DictationSession) {
        guard let review = pendingReview, let attention, let language = reviewLanguage else { return }
        let previous = snapshotOfReview(attention)
        let inModeStyle = reviewTone == session.dictationMode.effectiveStyle.tone
        guard machine.handle(.retry) else { return }
        reviewChange = .tone(previous: previous, previousTone: reviewTone, replacesFirst: inModeStyle)
        beginRetry()
        if inModeStyle {
            startRegeneration(review.original, for: session)
        } else {
            run(session) { processor, updates in
                await processor.restyle(review.original, style: review.style, language: language, for: session) {
                    updates.yield($0)
                }
            }
        }
    }

    /// Ends a review change that was processed. Returns whether `outcome` belonged to one.
    func finishReviewChange(_ outcome: DictationOutcome) -> Bool {
        guard let change = reviewChange else { return false }
        reviewChange = nil
        switch change {
        case .tone(let previous, let previousTone, let replacesFirst):
            guard case .review(let review, _) = outcome, let first = reviewFirst else {
                reviewTone = previousTone
                show(previous)
                finishSession(displayFor: attentionDisplay)
                return true
            }
            // A translation stays a translation (Translate Again is kept); a rewrite review stays one.
            let issue = first.issue.isRewriteReview ? DictationIssue.reviewRewrite(review.notice) : first.issue
            let shown = ReviewSnapshot(
                issue: issue, transcript: review.text, review: review, actions: actions(for: issue, previous))
            show(shown)
            if replacesFirst { reviewFirst = shown }
            feedback.announce(
                String(localized: "Dictation needs your attention. \(issue.userMessage)", bundle: .module))
            finishSession(displayFor: attentionDisplay)
        case .spokenLanguage(let translation):
            finishSpokenLanguage(outcome, translation: translation)
        }
        return true
    }

    /// Cancel while a review change runs goes back to the review instead of ending the
    /// session. Returns whether it did.
    func cancelReviewChange() -> Bool {
        guard reviewChange != nil, machine.state == .processing else { return false }
        stopProcessing()
        _ = finishReviewChange(.cancelled)
        return true
    }

    private func actions(for issue: DictationIssue, _ previous: ReviewSnapshot) -> [DictationAction] {
        if issue == previous.issue { return previous.actions }
        if let first = reviewFirst, issue == first.issue { return first.actions }
        return issue.actions(alternatives: []).filter(isOffered)
    }

    /// Puts `snapshot` on screen, moving the recorder to its issue.
    func show(_ snapshot: ReviewSnapshot) {
        switch machine.state {
        case .needsAttention(let current) where current == snapshot.issue:
            break
        case .needsAttention:
            guard machine.handle(.retry), machine.handle(.processingNeedsAttention(snapshot.issue)) else { return }
        default:
            guard machine.handle(.processingNeedsAttention(snapshot.issue)) else { return }
        }
        pendingTranscript = snapshot.transcript
        pendingReview = snapshot.review
        reviewShowsOriginal = false
        attentionActions = snapshot.actions
        sync()
    }
}
