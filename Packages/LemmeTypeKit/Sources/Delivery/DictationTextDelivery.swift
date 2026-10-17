import Domain
import Support

/// The production ``TextDelivering``: Accessibility insertion into the field
/// captured at activation (docs/decisions/0015-text-delivery.md).
///
/// Text is delivered at most once. A target that changed, a password field,
/// or missing Accessibility trust never receives text; the session keeps the
/// transcript so the user can Copy or Retry Insert.
public struct DictationTextDelivery<Driver: AccessibilityDriving>: TextDelivering {
    private let inserter: AccessibilityTextInserter<Driver>
    private let diagnostics: any DiagnosticsRecording

    public init(
        driver: Driver,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics(),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        inserter = AccessibilityTextInserter(driver: driver, sleep: sleep)
        self.diagnostics = diagnostics
    }

    public func deliver(_ text: String, to target: ActivationTarget?) async -> DeliveryOutcome {
        let outcome = await attempt(text, to: target)
        switch outcome {
        case .delivered(let method):
            diagnostics.record(.delivery, "delivery.delivered", ["method": .id(method.rawValue)])
        case .problem(let problem):
            diagnostics.record(.delivery, "delivery.problem", ["problem": .id(problem.rawValue)])
            Log.delivery.info("Delivery problem: \(problem.rawValue, privacy: .public)")
        }
        return outcome
    }

    private func attempt(_ text: String, to target: ActivationTarget?) async -> DeliveryOutcome {
        switch inserter.check(target) {
        case .problem(let problem):
            return .problem(problem)
        case .sameApplication:
            return .problem(.unsupported)
        case .focused(let element):
            switch await inserter.insert(text, into: element) {
            case .inserted:
                return .delivered(.accessibility)
            case .notInserted(let problem):
                return .problem(problem)
            case .uncertain:
                return .problem(.failed)
            }
        }
    }
}
