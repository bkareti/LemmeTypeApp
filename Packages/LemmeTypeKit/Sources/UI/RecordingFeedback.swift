import AppKit
import Domain

/// Non-visual feedback for recorder state changes.
@MainActor
public protocol RecordingFeedback: AnyObject {
    /// Spoken by VoiceOver (if running). Never includes audio levels or content.
    func announce(_ message: String)
    func play(_ sound: FeedbackSound)
}

public enum FeedbackSound: Sendable {
    case start
    case stop
}

/// VoiceOver announcements plus optional system sounds.
@MainActor
public final class SystemRecordingFeedback: RecordingFeedback {
    private let preferences: any AppPreferences

    public init(preferences: any AppPreferences) {
        self.preferences = preferences
    }

    public func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    public func play(_ sound: FeedbackSound) {
        guard preferences.playsFeedbackSounds else { return }
        NSSound(named: sound == .start ? "Tink" : "Pop")?.play()
    }
}
