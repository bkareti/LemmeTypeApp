import Domain

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

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

#if os(macOS)
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
#else
    /// VoiceOver announcements plus optional haptics. A haptic stands in for the
    /// Mac's sounds: the phone is usually silent, and the microphone is open.
    @MainActor
    public final class SystemRecordingFeedback: RecordingFeedback {
        private let preferences: any AppPreferences

        public init(preferences: any AppPreferences) {
            self.preferences = preferences
        }

        public func announce(_ message: String) {
            UIAccessibility.post(notification: .announcement, argument: message)
        }

        public func play(_ sound: FeedbackSound) {
            guard preferences.playsFeedbackSounds else { return }
            UIImpactFeedbackGenerator(style: sound == .start ? .medium : .light).impactOccurred()
        }
    }
#endif
