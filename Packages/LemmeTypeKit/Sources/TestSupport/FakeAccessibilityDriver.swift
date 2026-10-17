import Domain
import Synchronization

/// A text field in an imaginary app. Holds only a character count and a
/// selection, like the metadata the real driver may read.
public final class FakeTextElement: FocusedElementReference, Sendable {
    public struct Behavior: Sendable {
        public var isSecure = false
        public var acceptsSelectedText = true
        /// The app reports success for a write.
        public var reportsSuccess = true
        /// The app applies the write (Chromium-style apps report success but ignore it).
        public var appliesWrites = true
        /// Character count and selection are readable.
        public var exposesCount = true
        /// The change becomes visible only after this many reads.
        public var readsBeforeChangeIsVisible = 0

        public init() {}
    }

    private struct State {
        var text: String
        var selection: TextSelection
        var behavior: Behavior
        var writes: [String] = []
        var pastes: [String] = []
        var pendingReads = 0
        var visibleCount: Int?
    }

    public let processIdentifier: Int32
    private let state: Mutex<State>

    public init(
        processIdentifier: Int32 = 4242, text: String = "", selection: TextSelection? = nil,
        behavior: Behavior = Behavior()
    ) {
        self.processIdentifier = processIdentifier
        state = Mutex(
            State(
                text: text,
                selection: selection ?? TextSelection(location: text.utf16.count, length: 0),
                behavior: behavior))
    }

    public var handle: AnyObject { self }

    /// The field's content, for assertions only (the real driver cannot read it).
    public var text: String { state.withLock { $0.text } }
    /// Accessibility writes attempted.
    public var writes: [String] { state.withLock { $0.writes } }
    /// Text received through ⌘V.
    public var pastes: [String] { state.withLock { $0.pastes } }

    public func setText(_ text: String) {
        state.withLock {
            $0.text = text
            $0.selection = TextSelection(location: text.utf16.count, length: 0)
        }
    }

    var behavior: Behavior { state.withLock { $0.behavior } }

    var characterCount: Int? {
        state.withLock { state in
            guard state.behavior.exposesCount else { return nil }
            if state.pendingReads > 0 {
                state.pendingReads -= 1
                return state.visibleCount
            }
            return state.text.utf16.count
        }
    }

    var selection: TextSelection? {
        state.withLock { $0.behavior.exposesCount ? $0.selection : nil }
    }

    func write(_ inserted: String) -> Bool {
        state.withLock { state in
            state.writes.append(inserted)
            if state.behavior.appliesWrites {
                Self.apply(inserted, to: &state)
            }
            return state.behavior.reportsSuccess
        }
    }

    /// Paste always works in the fake app (it is a keyboard command).
    func paste(_ inserted: String) {
        state.withLock { state in
            state.pastes.append(inserted)
            Self.apply(inserted, to: &state)
        }
    }

    private static func apply(_ inserted: String, to state: inout State) {
        state.visibleCount = state.text.utf16.count
        state.pendingReads = state.behavior.readsBeforeChangeIsVisible
        var units = Array(state.text.utf16)
        let start = min(state.selection.location, units.count)
        let end = min(start + state.selection.length, units.count)
        units.replaceSubrange(start..<end, with: Array(inserted.utf16))
        state.text = String(decoding: units, as: UTF16.self)
        state.selection = TextSelection(location: start + inserted.utf16.count, length: 0)
    }
}

/// In-memory Accessibility: one focused element (or none) and a trust flag.
public final class FakeAccessibilityDriver: AccessibilityDriving {
    private struct State {
        var trusted: Bool
        var focused: FakeTextElement?
        var frontmost: Int32?
        var secureInput = false
        var readSecureField = false
    }

    private let state: Mutex<State>

    public init(trusted: Bool = true, focused: FakeTextElement? = nil, frontmost: Int32? = nil) {
        state = Mutex(State(trusted: trusted, focused: focused, frontmost: frontmost ?? focused?.processIdentifier))
    }

    public func focus(_ element: FakeTextElement?) {
        state.withLock {
            $0.focused = element
            $0.frontmost = element?.processIdentifier ?? $0.frontmost
        }
    }

    public func setFrontmost(_ processIdentifier: Int32?) {
        state.withLock { $0.frontmost = processIdentifier }
    }

    public func setTrusted(_ trusted: Bool) {
        state.withLock { $0.trusted = trusted }
    }

    public func setSecureInput(_ active: Bool) {
        state.withLock { $0.secureInput = active }
    }

    /// True if anything other than the secure-field check touched a secure field.
    public var readSecureField: Bool { state.withLock { $0.readSecureField } }

    /// A target captured with `element` focused, as the shortcut would capture it.
    public static func target(for element: FakeTextElement?, processIdentifier: Int32 = 4242) -> ActivationTarget {
        ActivationTarget(
            processIdentifier: element?.processIdentifier ?? processIdentifier, bundleIdentifier: "com.example.Editor",
            applicationName: "Editor", focusedElement: element)
    }

    public func isTrusted() -> Bool { state.withLock { $0.trusted } }

    public func element(from reference: any FocusedElementReference) -> FakeTextElement? {
        reference.handle as? FakeTextElement
    }

    public func focusedElement() -> (element: FakeTextElement, processIdentifier: Int32)? {
        state.withLock { state in state.focused.map { ($0, $0.processIdentifier) } }
    }

    public func frontmostProcessIdentifier() -> Int32? { state.withLock { $0.frontmost } }

    public func isSameElement(_ lhs: FakeTextElement, _ rhs: FakeTextElement) -> Bool { lhs === rhs }

    public func isSecureTextField(_ element: FakeTextElement) -> Bool { element.behavior.isSecure }

    public func isSecureInputActive() -> Bool { state.withLock { $0.secureInput } }

    public func canSetSelectedText(_ element: FakeTextElement) -> Bool {
        noteRead(element)
        return element.behavior.acceptsSelectedText
    }

    public func characterCount(of element: FakeTextElement) -> Int? {
        noteRead(element)
        return element.characterCount
    }

    public func selection(of element: FakeTextElement) -> TextSelection? {
        noteRead(element)
        return element.selection
    }

    public func setSelectedText(_ text: String, on element: FakeTextElement) -> Bool {
        noteRead(element)
        return element.write(text)
    }

    private func noteRead(_ element: FakeTextElement) {
        if element.behavior.isSecure {
            state.withLock { $0.readSecureField = true }
        }
    }
}
