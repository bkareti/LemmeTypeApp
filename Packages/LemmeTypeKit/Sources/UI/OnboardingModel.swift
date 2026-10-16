import Domain
import Observation
import Support

/// First-run flow. Each permission gets its own explanation screen, and the
/// system prompt is shown only when the user chooses to continue from it.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: Int, CaseIterable, Sendable {
        case welcome
        case microphone
        case accessibility
        case summary

        var permission: PermissionKind? {
            switch self {
            case .microphone: .microphone
            case .accessibility: .accessibility
            case .welcome, .summary: nil
            }
        }
    }

    public private(set) var step: Step = .welcome
    public let permissions: PermissionsModel

    private let preferences: any AppPreferences
    private let onFinish: @MainActor () -> Void

    public init(
        permissions: PermissionsModel,
        preferences: any AppPreferences,
        onFinish: @escaping @MainActor () -> Void
    ) {
        self.permissions = permissions
        self.preferences = preferences
        self.onFinish = onFinish
    }

    /// Setup can finish without every permission; the app then runs with the
    /// affected capabilities marked unavailable.
    public var isLimited: Bool { !permissions.allGranted }

    public func next() {
        guard let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
        permissions.refresh()
    }

    public func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Starts again from the first step, e.g. when reopened from the menu.
    public func restart() {
        step = .welcome
        permissions.refresh()
    }

    public func finish() {
        preferences.hasCompletedOnboarding = true
        Log.permissions.info("Onboarding finished; limited=\(self.isLimited, privacy: .public)")
        onFinish()
    }
}
