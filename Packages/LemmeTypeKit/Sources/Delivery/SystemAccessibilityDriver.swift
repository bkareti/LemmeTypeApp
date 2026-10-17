import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Domain

/// `AccessibilityDriving` backed by the macOS Accessibility API. Delivery reads
/// only role, subrole, character count, and selection range; bounded text is
/// read only through `text(in:of:)` for cursor context (ADR 0017).
public struct SystemAccessibilityDriver: AccessibilityDriving {
    /// An `AXUIElement`: an immutable CF reference that the Accessibility API
    /// allows using from any thread, so sharing it across tasks is safe.
    public final class Element: @unchecked Sendable {
        let element: AXUIElement

        init(_ element: AXUIElement) {
            self.element = element
        }
    }

    /// Upper bound on how long an unresponsive target app can block delivery
    /// per Accessibility call.
    private static let messagingTimeout: Float = 0.5

    public init() {}

    public func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func element(from reference: any FocusedElementReference) -> Element? {
        let handle = reference.handle as CFTypeRef
        guard CFGetTypeID(handle) == AXUIElementGetTypeID() else { return nil }
        // The type ID check above makes this cast safe.
        let element = unsafeDowncast(handle, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        return Element(element)
    }

    public func focusedElement() -> (element: Element, processIdentifier: Int32)? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
        guard let value = copy(kAXFocusedUIElementAttribute, of: systemWide),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return (Element(element), pid)
    }

    public func frontmostProcessIdentifier() -> Int32? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    public func isSameElement(_ lhs: Element, _ rhs: Element) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    public func isSecureTextField(_ handle: Element) -> Bool {
        let secure = kAXSecureTextFieldSubrole as String
        let element = handle.element
        return string(kAXRoleAttribute, of: element) == secure || string(kAXSubroleAttribute, of: element) == secure
    }

    public func isSecureInputActive() -> Bool {
        IsSecureEventInputEnabled()
    }

    public func canSetSelectedText(_ handle: Element) -> Bool {
        var settable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(handle.element, kAXSelectedTextAttribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    public func characterCount(of handle: Element) -> Int? {
        (copy(kAXNumberOfCharactersAttribute, of: handle.element) as? NSNumber)?.intValue
    }

    public func selection(of handle: Element) -> TextSelection? {
        guard let value = copy(kAXSelectedTextRangeAttribute, of: handle.element),
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return TextSelection(location: range.location, length: range.length)
    }

    public func setSelectedText(_ text: String, on handle: Element) -> Bool {
        AXUIElementSetAttributeValue(handle.element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    public func text(in range: TextSelection, of handle: Element) -> String? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            handle.element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    private func copy(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ attribute: String, of element: AXUIElement) -> String? {
        copy(attribute, of: element) as? String
    }
}
