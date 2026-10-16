import AppKit
import SwiftUI

/// Owns one app window (Settings, Onboarding): created on first use, reused
/// afterwards, and brought to the front each time it is requested. This is
/// what guarantees there is never more than one of each.
@MainActor
public final class ManagedWindowController {
    public let identifier: NSUserInterfaceItemIdentifier

    private var window: NSWindow?
    private let title: String
    private let makeRootView: @MainActor () -> AnyView

    public init(identifier: String, title: String, makeRootView: @escaping @MainActor () -> AnyView) {
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        self.title = title
        self.makeRootView = makeRootView
    }

    /// The window, if it has been created. Exposed for tests.
    public var currentWindow: NSWindow? { window }

    public var isVisible: Bool { window?.isVisible ?? false }

    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: makeRootView()))
        window.identifier = identifier
        window.setAccessibilityIdentifier(identifier.rawValue)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
