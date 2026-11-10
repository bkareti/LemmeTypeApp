import Domain
import Foundation
import Support

/// Processing and the decisions a ``DictationIssue`` offers.
extension RecordingCoordinator {
    /// Runs `session` through the processor. Updates and the outcome are
    /// applied only while `session` is still the current one, so a late result
    /// from a cancelled or replaced session can never change a later one.
    func startProcessing(_ session: DictationSession) {
        run(session) { processor, updates in
            await processor.process(session) { updates.yield($0) }
        }
    }

    /// Delivers an already produced transcript again (Retry Delivery).
    func startDelivery(_ transcript: String, for session: DictationSession) {
        run(session) { processor, _ in
            await processor.deliver(transcript, for: session)
        }
    }

    /// Rewrites the text under review again (Regenerate, E10-S4).
    func startRegeneration(_ original: String, for session: DictationSession) {
        run(session) { processor, updates in
            await processor.regenerate(original, for: session) { updates.yield($0) }
        }
    }

    private func run(
        _ session: DictationSession,
        work:
            @escaping @Sendable (any DictationProcessing, AsyncStream<ProcessingUpdate>.Continuation) async ->
            DictationOutcome
    ) {
        stopProcessing()
        markResidencyBusy(warmingUp: false)
        processingPhase = .preparingEngine
        processingProgress = nil
        let (updates, continuation) = AsyncStream.makeStream(of: ProcessingUpdate.self)
        let processor = self.processor
        let id = session.id
        updatesTask = Task { [weak self] in
            for await update in updates {
                self?.apply(update, for: id)
            }
        }
        processingTask = Task { [weak self] in
            let outcome = await work(processor, continuation)
            continuation.finish()
            self?.finishProcessing(id, outcome)
        }
    }

    func stopProcessing() {
        processingTask?.cancel()
        processingTask = nil
        updatesTask?.cancel()
        updatesTask = nil
        processingPhase = nil
        processingProgress = nil
    }

    private func apply(_ update: ProcessingUpdate, for id: UUID) {
        guard session?.id == id, state == .processing else { return }
        switch update {
        case .phase(let phase): processingPhase = phase
        case .progress(let fraction): processingProgress = fraction
        }
    }

    private func finishProcessing(_ id: UUID, _ outcome: DictationOutcome) {
        guard session?.id == id, state == .processing else { return }
        processingTask = nil
        processingPhase = nil
        processingProgress = nil
        switch outcome {
        case .delivered(let method):
            complete(with: method)
        case .needsAttention(let issue, let engine, let alternatives, let transcript):
            guard machine.handle(.processingNeedsAttention(issue)) else { return }
            if let engine { session?.engine = engine }
            pendingTranscript = transcript
            attentionActions = issue.actions(alternatives: alternatives).filter(isOffered)
            sync()
            feedback.announce(
                String(localized: "Dictation needs your attention. \(issue.userMessage)", bundle: .module))
            Log.recognition.info("Session needs attention: \(issue.identifier, privacy: .public)")
            finishSession(displayFor: attentionDisplay)
        case .review(let review, let engine):
            let issue = DictationIssue.reviewRewrite(review.notice)
            guard machine.handle(.processingNeedsAttention(issue)) else { return }
            if let engine { session?.engine = engine }
            pendingTranscript = review.text
            pendingReview = review
            reviewShowsOriginal = false
            attentionActions = issue.actions(alternatives: []).filter(isOffered)
            sync()
            feedback.announce(
                String(localized: "Dictation needs your attention. \(issue.userMessage)", bundle: .module))
            Log.recognition.info("Session needs attention: \(issue.identifier, privacy: .public)")
            finishSession(displayFor: attentionDisplay)
        case .cancelled:
            break
        }
    }

    /// Delivery finished (by the processor, or by the user choosing Copy).
    private func complete(with method: DeliveryMethod) {
        guard machine.handle(.processingFinished) else { return }
        lastDelivery = method
        discardSession()
        sync()
        feedback.announce(method.announcement)
        finishSession(displayFor: finishedDisplay)
    }

    func isOffered(_ action: DictationAction) -> Bool {
        switch action {
        case .allowSpeechRecognition: speechAuthorizer != nil
        case .copyText: textCopier != nil
        default: true
        }
    }

    /// Deletes the recording behind a result that has already been handed over,
    /// keeping the text in memory for Copy (ADR 0032). Choices that need the
    /// recording are no longer offered.
    public func discardRecordingKeepingText() {
        session?.discardAudio()
        attentionActions.removeAll { action in
            switch action {
            case .retry, .useEngine, .useLanguage, .saveAudio: true
            default: false
            }
        }
    }

    /// Deletes the kept recording and transcript.
    func discardSession() {
        session?.discardAudio()
        session = nil
        pendingTranscript = nil
        pendingReview = nil
        reviewShowsOriginal = false
        attentionActions = []
    }

    // MARK: Decisions

    /// Performs a choice offered for the current ``attention`` issue.
    public func perform(_ action: DictationAction) {
        enqueue { await $0.decide(action) }
    }

    private func decide(_ action: DictationAction) async {
        guard attention != nil, !decideWithoutRecording(action), let session else { return }
        switch action {
        case .retry, .useEngine:
            var next = session
            if case .useEngine(let engine) = action { next.engine = engine }
            self.session = next
            retry(next)
        case .useLanguage(let language):
            var next = session
            next.language = language
            self.session = next
            retry(next)
        case .copyText, .retryDelivery, .insertText, .useOriginal:
            await useTranscript(for: action, session: session)
        case .regenerate:
            guard let original = pendingReview?.original, machine.handle(.retry) else { return }
            beginRetry()
            startRegeneration(original, for: session)
        case .allowSpeechRecognition:
            await allowSpeechRecognition()
        case .saveAudio:
            await onSaveAudio(session.audio.fileURL)
        case .chooseEngine, .chooseLanguage, .openPermissions, .openContextSettings, .discard:
            break  // handled above
        }
    }

    /// Actions that need no recording (a refused voice edit has none).
    /// Returns whether `action` was one of them.
    private func decideWithoutRecording(_ action: DictationAction) -> Bool {
        switch action {
        case .chooseEngine, .chooseLanguage: onOpenSettings(.dictation)
        case .openPermissions: onOpenSettings(.permissions)
        case .openContextSettings: onOpenSettings(.context)
        case .discard: dismiss()
        default: return false
        }
        return true
    }

    /// Copy Text or Retry Insert with the transcript kept in memory.
    private func useTranscript(for action: DictationAction, session: DictationSession) async {
        // Use Original delivers the text from before the rewrite (E10-S4).
        if action == .useOriginal, let original = pendingReview?.original { pendingTranscript = original }
        // Copy copies what the review is showing.
        if action == .copyText, reviewShowsOriginal, let original = pendingReview?.original {
            pendingTranscript = original
        }
        guard let transcript = pendingTranscript else { return }
        if action == .copyText, let textCopier {
            await textCopier.copy(transcript)
            await history.record(transcript, for: session, delivery: .copied)
            complete(with: .copied)
        } else if action == .retryDelivery || action == .insertText || action == .useOriginal,
            machine.handle(.retry)
        {
            beginRetry()
            startDelivery(transcript, for: session)
        }
    }

    private func retry(_ session: DictationSession) {
        guard machine.handle(.retry) else { return }
        beginRetry()
        startProcessing(session)
    }

    private func beginRetry() {
        cancelPendingDismiss()
        attentionActions = []
        sync()
    }

    /// Prompts once; after a decision only System Settings can change it. The
    /// issue stays on screen so the user can Retry afterwards.
    private func allowSpeechRecognition() async {
        guard let speechAuthorizer else { return }
        if speechAuthorizer.status() == .notRequested {
            _ = await speechAuthorizer.requestAuthorization()
        } else {
            speechAuthorizer.openSystemSettings()
        }
    }
}
