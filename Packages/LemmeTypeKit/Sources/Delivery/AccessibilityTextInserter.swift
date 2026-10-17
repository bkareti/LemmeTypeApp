import Domain

/// Whether the field captured at activation still has focus.
enum TargetCheck<Element: Sendable>: Sendable {
    /// The captured element is focused again (or still).
    case focused(Element)
    /// The captured app is frontmost, but its element could not be compared
    /// (it was captured without one). Only the clipboard can be used.
    case sameApplication
    case problem(DeliveryProblem)
}

/// The result of one insertion attempt.
enum InsertionResult: Equatable, Sendable {
    case inserted
    /// Verified that nothing was inserted, so a fallback cannot duplicate text.
    case notInserted(DeliveryProblem)
    /// The target reported an error and the result cannot be verified. No
    /// automatic fallback runs, so text is never inserted twice.
    case uncertain
}

/// Inserts final text into the field captured at activation through
/// Accessibility (E2-S7, docs/decisions/0015-text-delivery.md).
///
/// Before inserting it checks that the same app and element have focus and
/// that the element is not a password field. Insertion sets the element's
/// selected text, which replaces a selection or inserts at the caret, exactly
/// once; success is verified from the character count and selection length,
/// never by reading text.
struct AccessibilityTextInserter<Driver: AccessibilityDriving>: Sendable {
    let driver: Driver
    /// How long to wait for an app that applies the change asynchronously.
    let settleDelay: Duration
    let sleep: @Sendable (Duration) async -> Void

    init(
        driver: Driver,
        settleDelay: Duration = .milliseconds(100),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.driver = driver
        self.settleDelay = settleDelay
        self.sleep = sleep
    }

    func check(_ target: ActivationTarget?) -> TargetCheck<Driver.Element> {
        guard let target else { return .problem(.noTarget) }
        guard driver.isTrusted() else { return .problem(.permissionMissing) }
        guard let reference = target.focusedElement, let captured = driver.element(from: reference) else {
            let frontmost = driver.focusedElement()?.processIdentifier ?? driver.frontmostProcessIdentifier()
            return frontmost == target.processIdentifier ? .sameApplication : .problem(.targetChanged)
        }
        guard let focused = driver.focusedElement(), focused.processIdentifier == target.processIdentifier,
            driver.isSameElement(focused.element, captured)
        else { return .problem(.targetChanged) }
        // Checked before anything else is read from the element.
        if driver.isSecureTextField(captured) { return .problem(.secureField) }
        return .focused(captured)
    }

    func insert(_ text: String, into element: Driver.Element) async -> InsertionResult {
        // Defence in depth: never type while macOS reports secure keyboard entry.
        if driver.isSecureInputActive() { return .notInserted(.secureField) }
        guard driver.canSetSelectedText(element) else { return .notInserted(.unsupported) }
        let before = driver.characterCount(of: element)
        let replacedLength = driver.selection(of: element)?.length ?? 0
        let expectedChange = text.utf16.count - replacedLength
        let accepted = driver.setSelectedText(text, on: element)

        guard let before else { return accepted ? .inserted : .uncertain }
        var after = driver.characterCount(of: element)
        if after == before && expectedChange != 0 {
            await sleep(settleDelay)
            after = driver.characterCount(of: element)
        }
        guard let after else { return accepted ? .inserted : .uncertain }
        if after != before || expectedChange == 0 {
            // Something changed (some apps report an error yet apply the
            // change), or a same-length selection was replaced.
            return accepted || after != before ? .inserted : .uncertain
        }
        // Nothing changed: the app ignores Accessibility writes (common in
        // Chromium and Electron apps) or refused this one.
        return .notInserted(accepted ? .unsupported : .failed)
    }
}
