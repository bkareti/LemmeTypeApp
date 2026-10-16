import Observation

/// Which settings pane is showing, so other parts of the app can deep-link.
@MainActor
@Observable
public final class SettingsNavigation {
    public enum Pane: String, Hashable, Sendable {
        case general
        case shortcut
        case audio
        case permissions
    }

    public var selectedPane: Pane = .general

    public init() {}
}
