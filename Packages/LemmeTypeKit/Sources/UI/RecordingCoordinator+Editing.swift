import Domain
import Support

/// Voice-editing refusals and the start announcement (E3-S5, E3-S6).
extension RecordingCoordinator {
    /// Voice editing can't start; nothing was recorded.
    func refuse(_ issue: DictationIssue) {
        guard machine.handle(.processingNeedsAttention(issue)) else { return }
        attentionActions = issue.actions(alternatives: []).filter(isOffered)
        sync()
        feedback.announce(String(localized: "Voice editing can’t start. \(issue.userMessage)", bundle: .module))
        Log.recognition.info("Voice edit refused: \(issue.identifier, privacy: .public)")
        finishSession(displayFor: failureDisplay)
    }

    func startAnnouncement(purpose: SessionPurpose, context: ContextCapture?) -> String {
        let started =
            purpose == .editing
            ? String(localized: "Editing selection. Say what to change.", bundle: .module)
            : String(localized: "Recording started", bundle: .module)
        guard let note = context?.statusText else { return started }
        return "\(started). \(note)"
    }
}
