/// Speech-recognition authorization, a macOS privacy permission separate from
/// Microphone. Only Apple Speech needs it, so it is requested when the user
/// chooses that engine or retries a session that needed it, never during
/// onboarding.
public protocol SpeechRecognitionAuthorizing: Sendable {
    /// Current status without prompting: `notRequested`, `granted`, `denied`, or `restricted`.
    func status() -> PermissionStatus
    /// Shows the system prompt if the user has not been asked; never re-prompts.
    func requestAuthorization() async -> PermissionStatus
    /// Opens System Settings › Privacy & Security › Speech Recognition.
    func openSystemSettings()
}
