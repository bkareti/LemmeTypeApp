import Domain
import Support

/// The production ``TextDelivering``: Accessibility insertion into the field
/// captured at activation, then the configured clipboard fallback when the
/// field verifiably did not take the text (docs/decisions/0015-text-delivery.md).
///
/// Text is delivered at most once. A target that changed, a password field,
/// or missing Accessibility trust never receives text; the session keeps the
/// transcript so the user can Copy or Retry Insert.
public struct DictationTextDelivery<Driver: AccessibilityDriving>: TextDelivering {
    private let inserter: AccessibilityTextInserter<Driver>
    private let paster: ClipboardPaster<Driver>
    private let pasteboard: any PasteboardAccessing
    private let policy: @Sendable () -> ClipboardFallbackPolicy
    private let diagnostics: any DiagnosticsRecording

    /// - Parameters:
    ///   - driver: Accessibility access.
    ///   - pasteboard: The clipboard used by the fallback.
    ///   - keystroke: Posts ⌘V for the fallback.
    ///   - policy: Read for every delivery, so a Settings change applies to
    ///     the next one.
    ///   - diagnostics: Receives outcome identifiers only.
    ///   - sleep: Injected for tests.
    public init(
        driver: Driver,
        pasteboard: any PasteboardAccessing,
        keystroke: any PasteKeystrokePosting,
        policy: @escaping @Sendable () -> ClipboardFallbackPolicy,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics(),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        inserter = AccessibilityTextInserter(driver: driver, sleep: sleep)
        paster = ClipboardPaster(
            driver: driver, pasteboard: pasteboard, keystroke: keystroke, diagnostics: diagnostics, sleep: sleep)
        self.pasteboard = pasteboard
        self.policy = policy
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
            return await fallBack(text, element: nil, reason: .unsupported)
        case .focused(let element):
            switch await inserter.insert(text, into: element) {
            case .inserted:
                return .delivered(.accessibility)
            case .notInserted(let problem) where problem == .unsupported || problem == .failed:
                return await fallBack(text, element: element, reason: problem)
            case .notInserted(let problem):
                return .problem(problem)
            case .uncertain:
                return .problem(.failed)
            }
        }
    }

    /// Only reached when nothing was inserted, so it can't duplicate text.
    private func fallBack(_ text: String, element: Driver.Element?, reason: DeliveryProblem) async
        -> DeliveryOutcome
    {
        let policy = policy()
        switch policy.fallback {
        case .off:
            return .problem(reason)
        case .copyOnly:
            await pasteboard.write(text)
            return .delivered(.copied)
        case .pasteAndRestore:
            let timing = PasteTiming(restoreDelay: .milliseconds(Int(policy.restoreDelay * 1000)))
            return await paster.paste(text, into: element, timing: timing)
        }
    }
}
