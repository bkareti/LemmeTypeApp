import Domain
import Foundation
import Observation
import Support

/// Watches the app's status file and inserts a finished dictation. Without Full
/// Access this keyboard can only read that file, so it polls: it has no
/// microphone, network, or speech code (ADR 0032).
@MainActor
@Observable
final class KeyboardVoiceModel {
    private(set) var handoff = KeyboardHandoff.idle

    @ObservationIgnored var insertText: (String) -> Void = { _ in }
    @ObservationIgnored var onOverlayChange: () -> Void = {}

    @ObservationIgnored private let store = AppGroupKeyboardHandoffStore.makeDefault()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastOverlay = false

    /// Stored in this keyboard's own container, so a result is inserted only once
    /// even if iOS replaces the keyboard while the result is still fresh.
    private static let insertedKey = "lastInsertedDictation"

    var isListening: Bool { handoff.phase == .listening }
    var isWriting: Bool { handoff.phase == .writing }
    var failureMessage: String? { handoff.phase == .failed ? handoff.failureMessage : nil }
    var showsOverlay: Bool { isListening || isWriting || failureMessage != nil }

    func start() {
        refresh()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refresh() {
        let current = store.read()
        if current != handoff { handoff = current }
        if showsOverlay != lastOverlay {
            lastOverlay = showsOverlay
            onOverlayChange()
        }
        let defaults = UserDefaults.standard
        let inserted = defaults.string(forKey: Self.insertedKey).flatMap(UUID.init(uuidString:))
        guard let insertion = current.insertion(now: .now, alreadyInserted: inserted) else { return }
        defaults.set(insertion.id.uuidString, forKey: Self.insertedKey)
        insertText(insertion.text)
    }
}
