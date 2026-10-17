import AppKit
import ApplicationServices
import Domain
import Support

/// Captures the frontmost app and, with Accessibility trust, a handle to its
/// focused element. It never reads the element's value or any other content.
@MainActor
public final class AccessibilityTargetCapturer: TargetCapturing {
    /// Upper bound on how long an unresponsive target app can delay activation.
    private static let messagingTimeout: Float = 0.25

    public init() {}

    public func captureTarget() -> ActivationTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXIsProcessTrusted() ? focusedElement(of: app.processIdentifier) : nil
        Log.shortcuts.debug("Captured target; hasElement=\(element != nil, privacy: .public)")
        return ActivationTarget(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            applicationName: app.localizedName,
            focusedElement: element
        )
    }

    private func focusedElement(of processIdentifier: pid_t) -> AXElementReference? {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(application, "AXFocusedUIElement" as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // The type ID check above makes this cast safe.
        return AXElementReference(element: unsafeDowncast(value, to: AXUIElement.self))
    }
}

/// Wraps an `AXUIElement` (an immutable CF reference that is safe to pass
/// between threads) so Domain code can carry it without importing AX.
public final class AXElementReference: FocusedElementReference, @unchecked Sendable {
    public let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    public var handle: AnyObject { element }
}
