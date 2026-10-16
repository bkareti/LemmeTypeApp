/// A macOS privacy permission LemmeType may need.
///
/// Only permissions with a shipped feature that requires them belong here.
/// Screen Recording and Input Monitoring are intentionally absent.
public enum PermissionKind: String, CaseIterable, Sendable {
    /// Microphone access, required to capture dictation audio.
    case microphone
    /// Accessibility trust, required to identify and insert into the focused field.
    case accessibility
}
