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

    private func run(
        _ session: DictationSession,
        work:
            @escaping @Sendable (any DictationProcessing, AsyncStream<ProcessingUpdate>.Continuation) async ->
            DictationOutcome
    ) {
        stopProcessing()
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

    /// Deletes the kept recording and transcript.
    func discardSession() {
        session?.discardAudio()
        session = nil
        pendingTranscript = nil
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
        case .copyText, .retryDelivery:
            await useTranscript(for: action, session: session)
        case .allowSpeechRecognition:
            await allowSpeechRecognition()
        case .saveAudio:
            await onSaveAudio(session.audio.fileURL)
        case .chooseEngine, .openPermissions, .openContextSettings, .discard:
            break  // handled above
        }
    }

    /// Actions that need no recording (a refused voice edit has none).
    /// Returns whether `action` was one of them.
    private func decideWithoutRecording(_ action: DictationAction) -> Bool {
        switch action {
        case .chooseEngine: onOpenSettings(.dictation)
        case .openPermissions: onOpenSettings(.permissions)
        case .openContextSettings: onOpenSettings(.context)
        case .discard: dismiss()
        default: return false
        }
        return true
    }

    /// Copy Text or Retry Insert with the transcript kept in memory.
    private func useTranscript(for action: DictationAction, session: DictationSession) async {
        guard let transcript = pendingTranscript else { return }
        if action == .copyText, let textCopier {
            await textCopier.copy(transcript)
            complete(with: .copied)
        } else if action == .retryDelivery, machine.handle(.retry) {
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
