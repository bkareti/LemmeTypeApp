import Foundation

/// How the dictation shortcut controls a session.
public enum ActivationMode: String, CaseIterable, Codable, Sendable {
    /// Hold to record; release to stop.
    case pushToTalk
    /// Press to start; press again to stop.
    case toggle
}

/// A raw hot-key event with the system uptime at which it happened.
public struct ShortcutEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case pressed
        case released
    }

    public let kind: Kind
    public let timestamp: TimeInterval

    public init(_ kind: Kind, at timestamp: TimeInterval) {
        self.kind = kind
        self.timestamp = timestamp
    }
}

/// The app and field that were focused when dictation was activated.
///
/// Held in memory for one session only so Epic 2 can deliver text back to it.
/// Nothing here reads the field's contents.
public struct ActivationTarget: Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?
    public let applicationName: String?
    /// Opaque reference to the focused element; `nil` without Accessibility trust.
    public let focusedElement: (any FocusedElementReference)?

    public init(
        processIdentifier: Int32,
        bundleIdentifier: String?,
        applicationName: String?,
        focusedElement: (any FocusedElementReference)?
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.focusedElement = focusedElement
    }
}

/// An opaque platform handle to a focused UI element. Only the platform
/// module that created it (Accessibility) knows what `handle` is.
public protocol FocusedElementReference: AnyObject, Sendable {
    var handle: AnyObject { get }
}

/// What the rest of the app should do in response to the shortcut.
public enum ActivationCommand: Sendable {
    case start(ActivationTarget?)
    case stop
    case cancel
}

/// Turns raw press/release events into start/stop decisions.
///
/// Guarantees at most one active session: key auto-repeat and presses while a
/// session is already starting are ignored, and presses that follow the
/// previous accepted press within ``debounceInterval`` are treated as bounce.
public struct ActivationInterpreter: Sendable {
    public enum Decision: Equatable, Sendable {
        case start
        case stop
        case ignore
    }

    public static let debounceInterval: TimeInterval = 0.15

    public var mode: ActivationMode
    public private(set) var isSessionActive = false
    private var isKeyDown = false
    private var lastAcceptedPress: TimeInterval?

    public init(mode: ActivationMode) {
        self.mode = mode
    }

    public mutating func handle(_ event: ShortcutEvent) -> Decision {
        switch event.kind {
        case .pressed:
            guard !isKeyDown else { return .ignore }  // auto-repeat
            isKeyDown = true
            if let last = lastAcceptedPress, event.timestamp - last < Self.debounceInterval {
                return .ignore
            }
            lastAcceptedPress = event.timestamp
            switch (mode, isSessionActive) {
            case (_, false):
                isSessionActive = true
                return .start
            case (.toggle, true):
                isSessionActive = false
                return .stop
            case (.pushToTalk, true):
                return .ignore
            }
        case .released:
            guard isKeyDown else { return .ignore }
            isKeyDown = false
            if mode == .pushToTalk && isSessionActive {
                isSessionActive = false
                return .stop
            }
            return .ignore
        }
    }

    /// The session ended for another reason (cancel, failure, quit).
    public mutating func sessionEnded() {
        isSessionActive = false
    }
}
