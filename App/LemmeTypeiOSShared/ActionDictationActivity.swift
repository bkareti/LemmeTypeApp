import ActivityKit
import AppIntents
import Foundation

/// Status only. A Live Activity can show on the Lock Screen, so it never carries
/// dictated text (ADR 0032).
struct ActionDictationAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: ActionDictationActivityStatus
        var startedAt: Date
    }
}

enum ActionDictationActivityStatus: String, Codable, Hashable {
    case listening
    case writing
    case failed
}

/// The Stop button in the Live Activity. Compiled into the app and the widget;
/// `ActionDictationBridge` is the app's real one and the widget's stand-in.
struct StopActionDictationIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Dictating"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        try await ActionDictationBridge.stop()
        return .result()
    }
}
