/// A product capability that depends on a macOS permission.
public enum Capability: String, CaseIterable, Sendable {
    /// Capturing dictation audio.
    case recording
    /// Identifying the focused field and inserting text into it.
    case textInsertion

    public var requiredPermission: PermissionKind {
        switch self {
        case .recording: .microphone
        case .textInsertion: .accessibility
        }
    }
}
