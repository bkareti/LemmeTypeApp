import Domain
import Support

/// Voice-editing refusals and the start announcement (E3-S5, E3-S6).
extension RecordingCoordinator {
    /// A session can't start; nothing was recorded. Voice editing (E3-S5) and
    /// an unavailable language or output (E9-S3) are refused this way.
    func refuse(_ issue: DictationIssue) {
        guard machine.handle(.processingNeedsAttention(issue)) else { return }
        attentionActions = issue.actions(alternatives: []).filter(isOffered)
        sync()
        let lead =
            if case .languageUnavailable = issue {
                String(localized: "Dictation can’t start.", bundle: .module)
            } else {
                String(localized: "Voice editing can’t start.", bundle: .module)
            }
        feedback.announce("\(lead) \(issue.userMessage)")
        Log.recognition.info("Session refused: \(issue.identifier, privacy: .public)")
        finishSession(displayFor: failureDisplay)
    }

    /// Refuses a dictation whose language or output can't run, before the user
    /// speaks (E9-S3). Returns whether it was refused.
    func refusesLanguage(for purpose: SessionPurpose) async -> Bool {
        guard purpose == .dictation, let settings = activeSettings,
            let issue = await processor.languageIssue(
                language: settings.language, output: settings.speechOutput,
                enginePreference: settings.enginePreference)
        else { return false }
        refuse(issue)
        return true
    }

    func startAnnouncement(purpose: SessionPurpose, context: ContextCapture?) -> String {
        let started =
            purpose == .editing
            ? String(localized: "Editing selection. Say what to change.", bundle: .module)
            : String(localized: "Recording started", bundle: .module)
        // Dictation names its mode (E4-S6) so VoiceOver users hear which one runs.
        let mode = purpose == .dictation ? activeDictationMode.map(\.displayName) : nil
        return [started, mode, context?.statusText].compactMap(\.self).joined(separator: ". ")
    }
}
