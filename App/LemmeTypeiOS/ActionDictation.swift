import ActivityKit
import AppIntents
import Domain
import UI
import UIKit

/// Lets intents reach the controller. A static is needed because the Stop intent
/// is compiled into the widget too, where this controller type does not exist.
enum ActionDictationBridge {
    @MainActor static var controller: ActionDictationController?

    @MainActor static func stop() async throws {
        controller?.stop()
    }
}

/// The Action Button: one press starts a dictation with the current app still in
/// front and the next press stops it (ADR 0032). It is declared only in the app
/// because the Action Button picker fails when the widget declares the same intent.
struct DictateAnywhereIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Dictate Anywhere"
    static let description = IntentDescription(
        "Starts or stops a dictation without leaving the current app. The text appears where you are typing when the LemmeType keyboard is open."
    )
    static var supportedModes: IntentModes { .background }
    // A press in a pocket must not turn on the microphone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        await ActionDictationBridge.controller?.toggle()
        return .result()
    }
}

@MainActor
struct IOSActionDictationPresenter: ActionDictationPresenting {
    func begin() throws {
        _ = try Activity.request(
            attributes: ActionDictationAttributes(),
            content: ActivityContent(
                state: ActionDictationAttributes.ContentState(status: .listening, startedAt: .now), staleDate: nil))
    }

    func show(_ status: ActionDictationStatus) async {
        await Self.update(to: status == .writing ? .writing : .failed)
    }

    func end() async {
        await Self.endAll()
    }

    // `Activity` is not Sendable, so these look activities up off the main actor
    // instead of passing a stored one across.
    private nonisolated static func update(to status: ActionDictationActivityStatus) async {
        let content = ActivityContent(
            state: ActionDictationAttributes.ContentState(status: status, startedAt: .now), staleDate: nil)
        for activity in Activity<ActionDictationAttributes>.activities { await activity.update(content) }
    }

    private nonisolated static func endAll() async {
        for activity in Activity<ActionDictationAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

@MainActor
final class IOSBackgroundTime: BackgroundTimeRequesting {
    private var task = UIBackgroundTaskIdentifier.invalid

    func begin(onExpire: @escaping @MainActor () -> Void) {
        guard task == .invalid else { return }
        task = UIApplication.shared.beginBackgroundTask(withName: "LemmeType dictation") { [weak self] in
            MainActor.assumeIsolated {
                onExpire()
                self?.end()
            }
        }
    }

    func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

extension IOSComposition {
    /// Dictation with another app in front (ADR 0032).
    struct ActionDictationServices {
        var handoff: any KeyboardHandoffPublishing = NoKeyboardHandoff()
        var presenter: any ActionDictationPresenting = NoActionDictationPresentation()
        var backgroundTime: any BackgroundTimeRequesting = NoBackgroundTime()
        var gate = BackgroundDictationGate()
    }
}

/// Runs only where there is no Live Activity or keyboard, such as UI tests.
struct NoActionDictationPresentation: ActionDictationPresenting {
    func begin() throws {}
    func show(_ status: ActionDictationStatus) async {}
    func end() async {}
}

struct NoBackgroundTime: BackgroundTimeRequesting {
    func begin(onExpire: @escaping @MainActor () -> Void) {}
    func end() {}
}

struct NoKeyboardHandoff: KeyboardHandoffPublishing {
    func publish(_ handoff: KeyboardHandoff) {}
    func clear() {}
}

/// Runs startup work once, whether the screen or an intent asks first.
@MainActor
final class StartupOnce {
    private var task: Task<Void, Never>?

    func run(_ work: @escaping @MainActor () async -> Void) async {
        if task == nil { task = Task { await work() } }
        await task?.value
    }
}
