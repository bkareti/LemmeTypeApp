import Observation

/// Which settings pane is showing, so other parts of the app can deep-link.
@MainActor
@Observable
public final class SettingsNavigation {
    public enum Pane: String, Hashable, Sendable {
        case general
        case dictation
        case shortcut
        case context
        case audio
        case permissions
        case privacy
        case diagnostics
    }

    public var selectedPane: Pane = .general

    /// The panes in tab-bar order.
    public static let order: [Pane] = [
        .general, .dictation, .shortcut, .context, .audio, .permissions, .privacy, .diagnostics,
    ]

    public init() {}

    /// ⌃Tab: the next pane, wrapping after the last (E7-S6, keyboard-only use).
    public func selectNext() { step(by: 1) }

    /// ⌃⇧Tab: the previous pane, wrapping before the first.
    public func selectPrevious() { step(by: -1) }

    private func step(by offset: Int) {
        let order = Self.order
        let index = order.firstIndex(of: selectedPane) ?? 0
        selectedPane = order[(index + offset + order.count) % order.count]
    }
}
