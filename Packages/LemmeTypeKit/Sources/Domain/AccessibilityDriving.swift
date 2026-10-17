/// A caret or selection in a text element, in UTF-16 code units (the unit
/// Accessibility uses).
public struct TextSelection: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// The Accessibility operations text delivery needs (E2-S7,
/// docs/decisions/0015-text-delivery.md).
///
/// Implementations never read an element's text value. They may read
/// metadata — role, subrole, character count, and selection range — and only
/// after the role check has ruled out a secure (password) field.
public protocol AccessibilityDriving: Sendable {
    associatedtype Element: Sendable

    /// Whether LemmeType is trusted for Accessibility.
    func isTrusted() -> Bool
    /// The element behind a captured ``ActivationTarget/focusedElement``, if
    /// it came from this driver.
    func element(from reference: any FocusedElementReference) -> Element?
    /// The element that has keyboard focus system-wide, with its process.
    func focusedElement() -> (element: Element, processIdentifier: Int32)?
    /// The frontmost application's process, when no element can be resolved.
    func frontmostProcessIdentifier() -> Int32?
    func isSameElement(_ lhs: Element, _ rhs: Element) -> Bool
    /// True for password fields (role or subrole `AXSecureTextField`).
    func isSecureTextField(_ element: Element) -> Bool
    /// Whether macOS reports secure keyboard entry (a password field has focus
    /// somewhere, or an app enabled secure input).
    func isSecureInputActive() -> Bool
    /// Whether the element accepts replacing its selection.
    func canSetSelectedText(_ element: Element) -> Bool
    func characterCount(of element: Element) -> Int?
    func selection(of element: Element) -> TextSelection?
    /// Replaces the selection (or inserts at the caret). Returns whether the
    /// target reported success.
    func setSelectedText(_ text: String, on element: Element) -> Bool
}
