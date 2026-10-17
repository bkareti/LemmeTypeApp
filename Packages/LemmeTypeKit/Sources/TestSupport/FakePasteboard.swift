import Domain
import Foundation
import Synchronization

/// An in-memory clipboard with a change count, like `NSPasteboard`.
public final class FakePasteboard: PasteboardAccessing {
    public static let plainText = "public.utf8-plain-text"

    private struct State {
        var items: [[String: Data]]
        var changeCount = 0
        /// Types whose data can't be read back (like file promises).
        var unreadableTypes: Set<String> = []
        var transientWrites = 0
        var restores = 0
    }

    private let state: Mutex<State>

    public init(items: [[String: Data]] = [], unreadableTypes: Set<String> = []) {
        state = Mutex(State(items: items, unreadableTypes: unreadableTypes))
    }

    public var items: [[String: Data]] { state.withLock { $0.items } }
    public var string: String? {
        state.withLock { $0.items.first?[Self.plainText].flatMap { String(bytes: $0, encoding: .utf8) } }
    }
    public var restoreCount: Int { state.withLock { $0.restores } }
    public var transientWriteCount: Int { state.withLock { $0.transientWrites } }

    /// Another app (or the user) copies something.
    public func userCopies(_ text: String) {
        state.withLock {
            $0.items = [[Self.plainText: Data(text.utf8)]]
            $0.changeCount += 1
        }
    }

    public func changeCount() async -> Int { state.withLock { $0.changeCount } }

    public func snapshot() async -> PasteboardSnapshot {
        state.withLock { state in
            let complete = state.items.allSatisfy { Set($0.keys).isDisjoint(with: state.unreadableTypes) }
            let readable = state.items.map { $0.filter { !state.unreadableTypes.contains($0.key) } }
            return PasteboardSnapshot(items: readable, isComplete: complete)
        }
    }

    public func writeTransient(_ text: String) async -> Int {
        state.withLock {
            $0.items = [[Self.plainText: Data(text.utf8), "org.nspasteboard.TransientType": Data()]]
            $0.changeCount += 1
            $0.transientWrites += 1
            return $0.changeCount
        }
    }

    public func write(_ text: String) async {
        userCopies(text)
    }

    public func restore(_ snapshot: PasteboardSnapshot) async {
        state.withLock {
            $0.items = snapshot.items
            $0.changeCount += 1
            $0.restores += 1
        }
    }
}

/// Simulates ⌘V: the focused fake field takes whatever is on the fake
/// clipboard, unless the app is configured to ignore the paste.
public final class FakePasteKeystroke: PasteKeystrokePosting {
    private struct State {
        var posts = 0
        var consumes = true
        var succeeds = true
    }

    private let state = Mutex(State())
    private let pasteboard: FakePasteboard
    private let driver: FakeAccessibilityDriver
    /// Runs right after the paste, e.g. to simulate the user copying.
    private let afterPaste: @Sendable () -> Void

    public init(
        pasteboard: FakePasteboard, driver: FakeAccessibilityDriver, consumes: Bool = true, succeeds: Bool = true,
        afterPaste: @escaping @Sendable () -> Void = {}
    ) {
        self.pasteboard = pasteboard
        self.driver = driver
        self.afterPaste = afterPaste
        state.withLock {
            $0.consumes = consumes
            $0.succeeds = succeeds
        }
    }

    public var postCount: Int { state.withLock { $0.posts } }

    public func postPaste() -> Bool {
        let (consumes, succeeds) = state.withLock { state in
            state.posts += 1
            return (state.consumes, state.succeeds)
        }
        guard succeeds else { return false }
        if consumes, let text = pasteboard.string, let field = driver.focusedElement()?.element {
            field.paste(text)
        }
        afterPaste()
        return true
    }
}
