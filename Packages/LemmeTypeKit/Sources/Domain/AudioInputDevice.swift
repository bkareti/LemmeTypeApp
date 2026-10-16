/// A microphone or other audio input that LemmeType can record from.
public struct AudioInputDevice: Hashable, Identifiable, Sendable {
    /// Stable identifier from the operating system, persisted as the user's selection.
    public let id: String
    /// Human-readable device name shown in settings.
    public let name: String
    /// Whether this is the current system default input.
    public let isSystemDefault: Bool

    public init(id: String, name: String, isSystemDefault: Bool) {
        self.id = id
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}
