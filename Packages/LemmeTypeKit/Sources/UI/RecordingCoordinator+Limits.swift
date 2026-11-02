import Domain
import Foundation

/// Ending a recording for the platform, not the user (E8-S4, ADR 0027).
extension RecordingCoordinator {
    /// Ends a recording the system is about to take away from the user: the app
    /// left the foreground, or memory is critical (E8-S4). What was captured is
    /// processed as if the user had pressed Stop, so a dictation is not lost,
    /// and nothing keeps the microphone open. Does nothing outside a recording.
    public func stopForSystemReason() {
        switch state {
        case .preparing: requestCancel()
        case .recording: requestStop()
        default: break
        }
    }

    /// Stops the recording when it reaches its maximum duration (E8-S4).
    func startLimitTimer() {
        guard let maximum = limits.maximumDuration else { return }
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: maximum)
            guard !Task.isCancelled, let self, self.state == .recording else { return }
            self.feedback.announce(String(localized: "Recording stopped: time limit reached", bundle: .module))
            self.requestStop()
        }
    }

    func cancelLimitTimer() {
        limitTask?.cancel()
        limitTask = nil
    }
}
