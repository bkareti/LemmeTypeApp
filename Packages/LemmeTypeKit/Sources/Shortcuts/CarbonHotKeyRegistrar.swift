import Carbon.HIToolbox
import Domain
import Support

/// System-wide hot keys through Carbon's `RegisterEventHotKey`, which reports
/// both press and release and needs no Input Monitoring permission. Events are
/// delivered on the main thread without activating LemmeType.
@MainActor
public final class CarbonHotKeyRegistrar: HotKeyRegistering {
    /// "LmTy" — identifies LemmeType's hot keys in Carbon events.
    private static let signature: OSType = 0x4C6D_5479

    private var handlers: [UInt32: @MainActor (ShortcutEvent) -> Void] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    public init() {}

    isolated deinit {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    public func register(
        _ shortcut: KeyboardShortcut,
        onEvent: @escaping @MainActor (ShortcutEvent) -> Void
    ) throws(ShortcutError) -> any HotKeyRegistration {
        try installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            Log.shortcuts.error("Hot key registration failed: \(status, privacy: .public)")
            throw status == eventHotKeyExistsErr ? .unavailable : .registrationFailed(code: status)
        }
        handlers[id] = onEvent
        return CarbonHotKeyRegistration(reference: reference) { [weak self] in
            self?.handlers[id] = nil
        }
    }

    nonisolated static func carbonModifiers(_ modifiers: KeyboardShortcut.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    fileprivate func dispatch(id: UInt32, event: ShortcutEvent) {
        handlers[id]?(event)
    }

    private func installEventHandlerIfNeeded() throws(ShortcutError) {
        guard eventHandler == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventCallback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { throw .registrationFailed(code: status) }
    }
}

/// Carbon delivers hot-key events on the main thread's event loop.
private func hotKeyEventCallback(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let kind: ShortcutEvent.Kind = GetEventKind(event) == UInt32(kEventHotKeyPressed) ? .pressed : .released
    let shortcutEvent = ShortcutEvent(kind, at: GetEventTime(event))
    let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        registrar.dispatch(id: hotKeyID.id, event: shortcutEvent)
    }
    return noErr
}

@MainActor
private final class CarbonHotKeyRegistration: HotKeyRegistration {
    private var reference: EventHotKeyRef?
    private let onUnregister: @MainActor () -> Void

    init(reference: EventHotKeyRef, onUnregister: @escaping @MainActor () -> Void) {
        self.reference = reference
        self.onUnregister = onUnregister
    }

    func unregister() {
        guard let reference else { return }
        UnregisterEventHotKey(reference)
        self.reference = nil
        onUnregister()
    }

    isolated deinit {
        unregister()
    }
}
