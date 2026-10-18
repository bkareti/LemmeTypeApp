import Domain

extension AudioCaptureError {
    /// Concise, actionable text for the overlay and settings.
    var userMessage: String {
        switch self {
        case .microphonePermissionMissing:
            String(localized: "Microphone access is off. Allow it in the Permissions pane.", bundle: .module)
        case .noInputDevice:
            String(localized: "No microphone is available. Connect one and try again.", bundle: .module)
        case .deviceDisconnected:
            String(localized: "The microphone was disconnected. Choose another input and try again.", bundle: .module)
        case .interrupted:
            String(localized: "Recording was interrupted. Try again.", bundle: .module)
        case .engineFailure, .alreadyCapturing, .notCapturing:
            String(localized: "The microphone couldn’t be started. Try again or choose another input.", bundle: .module)
        case .insufficientStorage:
            String(
                localized: "Not enough disk space to record. Free at least 100 MB and try again.", bundle: .module)
        case .storageFailure:
            String(
                localized: "LemmeType couldn’t create a temporary recording. Check free disk space.", bundle: .module)
        }
    }
}
