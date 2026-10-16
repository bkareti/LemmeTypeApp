import Domain

/// Records registrations and lets tests deliver press/release events.
@MainActor
public final class FakeHotKeyRegistrar: HotKeyRegistering {
    private final class Registration: HotKeyRegistration {
        let shortcut: KeyboardShortcut
        let onEvent: @MainActor (ShortcutEvent) -> Void
        weak var owner: FakeHotKeyRegistrar?

        init(shortcut: KeyboardShortcut, onEvent: @escaping @MainActor (ShortcutEvent) -> Void) {
            self.shortcut = shortcut
            self.onEvent = onEvent
        }

        func unregister() {
            owner?.active.removeAll { $0 === self }
        }
    }

    private var active: [Registration] = []
    /// Shortcuts that fail to register with the given error.
    public var failures: [KeyboardShortcut: ShortcutError] = [:]
    public private(set) var registrationCount = 0

    public init() {}

    public var registeredShortcuts: [KeyboardShortcut] { active.map(\.shortcut) }

    public func register(
        _ shortcut: KeyboardShortcut,
        onEvent: @escaping @MainActor (ShortcutEvent) -> Void
    ) throws(ShortcutError) -> any HotKeyRegistration {
        if let error = failures[shortcut] { throw error }
        if active.contains(where: { $0.shortcut == shortcut }) { throw .unavailable }
        let registration = Registration(shortcut: shortcut, onEvent: onEvent)
        registration.owner = self
        active.append(registration)
        registrationCount += 1
        return registration
    }

    /// Delivers an event as if the user pressed or released `shortcut`.
    /// Returns `false` if nothing is registered for it.
    @discardableResult
    public func send(_ kind: ShortcutEvent.Kind, _ shortcut: KeyboardShortcut, at timestamp: Double) -> Bool {
        guard let registration = active.first(where: { $0.shortcut == shortcut }) else { return false }
        registration.onEvent(ShortcutEvent(kind, at: timestamp))
        return true
    }
}

/// Returns a fixed target and counts how often it was asked.
@MainActor
public final class FakeTargetCapturer: TargetCapturing {
    public var target: ActivationTarget?
    public private(set) var captureCount = 0

    public init(target: ActivationTarget? = FakeTargetCapturer.textEdit) {
        self.target = target
    }

    public func captureTarget() -> ActivationTarget? {
        captureCount += 1
        return target
    }

    public static let textEdit = ActivationTarget(
        processIdentifier: 4242,
        bundleIdentifier: "com.apple.TextEdit",
        applicationName: "TextEdit",
        focusedElement: nil
    )
}
