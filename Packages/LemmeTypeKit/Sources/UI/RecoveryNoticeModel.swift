import Observation

/// The one-time menu notice after an unexpected end (E7-S4). It lives for this
/// run only: a normal quit means the next launch shows nothing.
@MainActor
@Observable
public final class RecoveryNoticeModel {
    public private(set) var isVisible: Bool
    /// Whether the previous run ended unexpectedly; stays true after Dismiss, for the support report.
    public private(set) var previousRunEndedUnexpectedly: Bool
    /// The version that was running when the app ended unexpectedly, if known.
    public private(set) var previousVersion: String?

    public init(previousRunEndedUnexpectedly: Bool = false, previousVersion: String? = nil) {
        isVisible = previousRunEndedUnexpectedly
        self.previousRunEndedUnexpectedly = previousRunEndedUnexpectedly
        self.previousVersion = previousVersion
    }

    public func show(previousVersion: String?) {
        isVisible = true
        previousRunEndedUnexpectedly = true
        self.previousVersion = previousVersion
    }

    public func dismiss() {
        isVisible = false
    }
}
