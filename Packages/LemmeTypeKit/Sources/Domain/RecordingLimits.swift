/// How long one recording may run before LemmeType stops it (ADR 0027).
public struct RecordingLimits: Equatable, Sendable {
    /// `nil` means no limit.
    public let maximumDuration: Duration?

    public init(maximumDuration: Duration?) {
        self.maximumDuration = maximumDuration
    }

    /// The Mac: the user stops the recording; there is no timer.
    public static let none = RecordingLimits(maximumDuration: nil)
    /// iPhone and iPad: five minutes (Proposed). A forgotten recording must not keep the microphone open.
    public static let handheld = RecordingLimits(maximumDuration: .seconds(300))
}
