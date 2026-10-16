import AppKit
import SwiftUI

/// Owns the single settings window: created on first use, reused afterwards,
/// and brought to the front each time it is requested.
@MainActor
public final class SettingsWindowController {
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("settings")

    private var window: NSWindow?
    private let makeRootView: @MainActor () -> AnyView

    public init(makeRootView: @escaping @MainActor () -> AnyView) {
        self.makeRootView = makeRootView
    }

    /// The window, if it has been created. Exposed for tests.
    public var currentWindow: NSWindow? { window }

    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: makeRootView()))
        window.identifier = Self.windowIdentifier
        window.setAccessibilityIdentifier(Self.windowIdentifier.rawValue)
        window.title = String(localized: "LemmeType Settings", bundle: .module)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
