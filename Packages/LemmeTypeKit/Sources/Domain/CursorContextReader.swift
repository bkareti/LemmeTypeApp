/// Reads bounded context for a just-captured target (E3-S2,
/// docs/decisions/0017-cursor-context.md).
///
/// Checks run in a fixed order and stop at the first failure, so nothing is
/// read from an excluded app, a password field, or while secure keyboard
/// entry is on: app policy → Accessibility trust → element → password field
/// → secure input → selection → text.
public struct CursorContextReader<Driver: AccessibilityDriving>: Sendable {
    private let driver: Driver
    private let policy: @Sendable () -> ContextPolicy

    /// `policy` is read for every activation, so Settings changes apply to
    /// the next one.
    public init(driver: Driver, policy: @escaping @Sendable () -> ContextPolicy) {
        self.driver = driver
        self.policy = policy
    }

    public func read(for target: ActivationTarget, purpose: ContextPurpose) -> ContextCapture {
        do {
            return .captured(try capture(target, purpose: purpose), purpose: purpose)
        } catch {
            return .blocked(error.reason, purpose: purpose)
        }
    }

    private struct Blocked: Error {
        let reason: ContextBlockReason
        init(_ reason: ContextBlockReason) { self.reason = reason }
    }

    private func capture(_ target: ActivationTarget, purpose: ContextPurpose) throws(Blocked) -> CursorContext {
        let element = try readableElement(of: target, purpose: purpose)
        guard let selection = driver.selection(of: element) else { throw Blocked(.unreadable) }
        let selectedText = purpose == .editing ? try self.selectedText(selection, of: element) : nil
        let preceding = try precedingText(before: selection, of: element, purpose: purpose)
        let following = followingText(after: selection, of: element)
        guard
            let context = CursorContext(
                precedingText: preceding, followingText: following, selection: selection,
                selectedText: selectedText)
        else {
            // The app returned more than was asked for; use none of it.
            throw Blocked(.unreadable)
        }
        return context
    }

    /// Policy, trust, element, and secure checks — before any text is read.
    private func readableElement(of target: ActivationTarget, purpose: ContextPurpose) throws(Blocked)
        -> Driver.Element
    {
        if let reason = policy().blockReason(for: purpose, bundleIdentifier: target.bundleIdentifier) {
            throw Blocked(reason)
        }
        guard driver.isTrusted() else { throw Blocked(.noAccessibility) }
        guard let reference = target.focusedElement, let element = driver.element(from: reference) else {
            throw Blocked(.unreadable)
        }
        if driver.isSecureTextField(element) { throw Blocked(.secureField) }
        if driver.isSecureInputActive() { throw Blocked(.secureInput) }
        return element
    }

    private func selectedText(_ selection: TextSelection, of element: Driver.Element) throws(Blocked) -> String {
        guard selection.length > 0 else { throw Blocked(.noSelection) }
        guard selection.length <= CursorContext.maxSelectionLength else { throw Blocked(.selectionTooLong) }
        guard let text = driver.text(in: selection, of: element), !text.isEmpty else { throw Blocked(.unreadable) }
        return text
    }

    /// Formatting needs the preceding text; editing only needs the selection.
    private func precedingText(before selection: TextSelection, of element: Driver.Element, purpose: ContextPurpose)
        throws(Blocked) -> String
    {
        let start = max(0, selection.location - CursorContext.maxPrecedingLength)
        let range = TextSelection(location: start, length: selection.location - start)
        guard range.length > 0 else { return "" }
        if let text = driver.text(in: range, of: element) { return text }
        if purpose == .formatting { throw Blocked(.unreadable) }
        return ""
    }

    /// Up to ``CursorContext/maxFollowingLength`` after the selection; empty
    /// when the count is unknown (an out-of-range request fails in most apps).
    private func followingText(after selection: TextSelection, of element: Driver.Element) -> String {
        let end = selection.location + selection.length
        guard let count = driver.characterCount(of: element), count > end else { return "" }
        let range = TextSelection(location: end, length: min(CursorContext.maxFollowingLength, count - end))
        return driver.text(in: range, of: element) ?? ""
    }
}
