import AppIntents
import Domain

/// Starts Quick Dictation from the Action Button, Back Tap, Siri, or the
/// Shortcuts app (E8-S7). The intent only opens the app and leaves a one-time
/// request; the app starts recording once its screen is showing, so the
/// recording is always visible. It needs an unlocked device.
struct StartQuickDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Dictating"
    static let description = IntentDescription(
        "Opens LemmeType and starts recording. The text stays on your device until you copy it.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Dependency private var launchRequests: LaunchRequestInbox

    func perform() async throws -> some IntentResult {
        launchRequests.post()
        return .result()
    }
}

struct LemmeTypeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartQuickDictationIntent(),
            phrases: [
                "Start dictating with \(.applicationName)",
                "Dictate with \(.applicationName)",
            ],
            shortTitle: "Start Dictating",
            systemImageName: "mic.fill")
    }
}
