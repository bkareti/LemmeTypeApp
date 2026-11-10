import Domain
import Foundation
import Testing

/// ADR 0032: what the keyboard may insert, given that it cannot report back.
struct KeyboardHandoffTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func aFreshResultIsInserted() {
        let id = UUID()
        let handoff = KeyboardHandoff.ready(text: "Hello", id: id, at: now)
        #expect(handoff.insertion(now: now.addingTimeInterval(1), alreadyInserted: nil)?.text == "Hello")
        #expect(handoff.insertion(now: now.addingTimeInterval(1), alreadyInserted: nil)?.id == id)
    }

    @Test func aResultIsNeverInsertedTwice() {
        let id = UUID()
        let handoff = KeyboardHandoff.ready(text: "Hello", id: id, at: now)
        #expect(handoff.insertion(now: now, alreadyInserted: id) == nil)
    }

    @Test func aStaleResultIsIgnored() {
        let handoff = KeyboardHandoff.ready(text: "Hello", at: now)
        #expect(handoff.insertion(now: now.addingTimeInterval(KeyboardHandoff.lifetime), alreadyInserted: nil) == nil)
    }

    @Test func aResultFromTheFutureIsIgnored() {
        let handoff = KeyboardHandoff.ready(text: "Hello", at: now)
        #expect(handoff.insertion(now: now.addingTimeInterval(-1), alreadyInserted: nil) == nil)
    }

    @Test(arguments: [KeyboardHandoff.Phase.idle, .listening, .writing, .failed])
    func onlyAReadyResultIsInserted(phase: KeyboardHandoff.Phase) {
        let handoff = KeyboardHandoff(phase: phase, resultID: UUID(), text: "Hello", createdAt: now)
        #expect(handoff.insertion(now: now, alreadyInserted: nil) == nil)
    }

    @Test func theDescriptionNeverContainsTheText() {
        let canary = "CANARY-private-words"
        #expect(!KeyboardHandoff.ready(text: canary).description.contains(canary))
    }
}
