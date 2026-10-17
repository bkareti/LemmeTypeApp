import AppKit
import ApplicationServices
import Domain
import Support

/// Captures the frontmost app and, with Accessibility trust, a handle to its
/// focused element. Field text is read only by `readContext` (a
/// `CursorContextReader` supplied by the composition root, ADR 0017), at this
/// moment and within its bounds.
@MainActor
public final class AccessibilityTargetCapturer: TargetCapturing {
    /// Upper bound on how long an unresponsive target app can delay activation.
    private static let messagingTimeout: Float = 0.25

    private let readContext: @MainActor (ActivationTarget, ContextPurpose) -> ContextCapture

    public init(
        readContext: @escaping @MainActor (ActivationTarget, ContextPurpose) -> ContextCapture = { _, _ in
            .notRequested
        }
    ) {
        self.readContext = readContext
    }

    public func captureTarget(purpose: ContextPurpose) -> ActivationTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXIsProcessTrusted() ? focusedElement(of: app.processIdentifier) : nil
        Log.shortcuts.debug("Captured target; hasElement=\(element != nil, privacy: .public)")
        let target = ActivationTarget(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            applicationName: app.localizedName,
            focusedElement: element
        )
        return target.with(context: readContext(target, purpose))
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
