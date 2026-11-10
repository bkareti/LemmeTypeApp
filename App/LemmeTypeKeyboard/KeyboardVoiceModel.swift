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
    /// A result that may belong to another field, waiting for a tap.
    private(set) var offered: KeyboardHandoff.Insertion?

    @ObservationIgnored var insertText: (String) -> Void = { _ in }
    @ObservationIgnored var currentField: () -> UUID? = { nil }
    @ObservationIgnored var onOverlayChange: () -> Void = {}

    @ObservationIgnored private let store = AppGroupKeyboardHandoffStore.makeDefault()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastOverlay = false
    @ObservationIgnored private var hasRefreshed = false
    /// The field open when this keyboard saw the recording start.
    @ObservationIgnored private var recordingField: UUID?

    /// Stored in this keyboard's own container, so a result is inserted only once
    /// even if iOS replaces the keyboard while the result is still fresh.
    private static let insertedKey = "lastInsertedDictation"

    var isListening: Bool { handoff.phase == .listening }
    var isWriting: Bool { handoff.phase == .writing }
    var failureMessage: String? { handoff.phase == .failed ? handoff.failureMessage : nil }
    var showsOverlay: Bool { isListening || isWriting || failureMessage != nil || offered != nil }

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

    func insertOffered() {
        guard let offered else { return }
        markUsed(offered.id)
        insertText(offered.text)
        self.offered = nil
        updateOverlay()
    }

    func dismissOffered() {
        guard let offered else { return }
        markUsed(offered.id)
        self.offered = nil
        updateOverlay()
    }

    private func refresh() {
        let current = store.read()
        // Seeing the start matters: a keyboard opened mid-recording may be in another field.
        if current.phase == .listening, handoff.phase != .listening, hasRefreshed {
            recordingField = currentField()
        }
        hasRefreshed = true
        if current != handoff { handoff = current }
        deliver(current)
        updateOverlay()
    }

    private func deliver(_ current: KeyboardHandoff) {
        let inserted = UserDefaults.standard.string(forKey: Self.insertedKey).flatMap(UUID.init(uuidString:))
        switch current.delivery(
            now: .now, alreadyInserted: inserted, recordingField: recordingField, currentField: currentField())
        {
        case .none:
            offered = nil
        case .offer(let insertion):
            if offered != insertion { offered = insertion }
        case .insert(let insertion):
            markUsed(insertion.id)
            recordingField = nil
            offered = nil
            insertText(insertion.text)
        }
    }

    private func markUsed(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: Self.insertedKey)
    }

    private func updateOverlay() {
        guard showsOverlay != lastOverlay else { return }
        lastOverlay = showsOverlay
        onOverlayChange()
    }
}
