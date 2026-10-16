import AppKit
import Observation
import SwiftUI

/// Shows the recorder overlay in a floating panel that never becomes key or
/// main, so the user's text field keeps focus throughout dictation.
@MainActor
public final class RecordingOverlayController {
    public static let identifier = "recording-overlay"

    private let coordinator: RecordingCoordinator
    private var panel: NSPanel?

    public init(coordinator: RecordingCoordinator) {
        self.coordinator = coordinator
    }

    public var isVisible: Bool { panel?.isVisible ?? false }
    public var currentPanel: NSPanel? { panel }

    /// Begins following the coordinator's state.
    public func start() {
        withObservationTracking {
            _ = coordinator.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.start()
            }
        }
        sync()
    }

    private func sync() {
        if coordinator.state == .idle {
            panel?.orderOut(nil)
        } else {
            show()
        }
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()  // visible without activating LemmeType
    }

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 90),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: RecordingOverlayView(coordinator: coordinator))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        panel.setAccessibilityIdentifier(Self.identifier)
        panel.identifier = NSUserInterfaceItemIdentifier(Self.identifier)
        return panel
    }

    /// Top centre of the screen with the pointer, just below the menu bar.
    private func position(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else {
            return
        }
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let frame = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: frame.midX - size.width / 2, y: frame.maxY - size.height - 12, width: size.width, height: size.height
            ),
            display: true
        )
    }
}

/// A panel that accepts clicks on its buttons but never takes keyboard focus.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
