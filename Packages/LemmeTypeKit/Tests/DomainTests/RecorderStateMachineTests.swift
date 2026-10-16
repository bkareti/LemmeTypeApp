import Domain
import Testing

struct RecorderStateMachineTests {
    private static let allStates: [RecorderState] = [
        .idle, .preparing, .recording, .stopping, .processing, .completed, .cancelled, .failed(.interrupted),
    ]
    private static let allEvents: [RecorderEvent] = [
        .activate, .captureStarted, .stopRequested, .captureFinished, .processingFinished, .cancel,
        .fail(.deviceDisconnected), .reset,
    ]

    struct Transition: Sendable, CustomTestStringConvertible {
        let from: RecorderState
        let event: RecorderEvent
        let expected: RecorderState

        init(_ from: RecorderState, _ event: RecorderEvent, _ expected: RecorderState) {
            self.from = from
            self.event = event
            self.expected = expected
        }

        var testDescription: String { "\(from) + \(event) → \(expected)" }
    }

    private static let valid: [Transition] = [
        Transition(.idle, .activate, .preparing),
        Transition(.preparing, .captureStarted, .recording),
        Transition(.preparing, .cancel, .cancelled),
        Transition(.preparing, .fail(.deviceDisconnected), .failed(.deviceDisconnected)),
        Transition(.recording, .stopRequested, .stopping),
        Transition(.recording, .cancel, .cancelled),
        Transition(.recording, .fail(.deviceDisconnected), .failed(.deviceDisconnected)),
        Transition(.stopping, .captureFinished, .processing),
        Transition(.stopping, .fail(.deviceDisconnected), .failed(.deviceDisconnected)),
        Transition(.processing, .processingFinished, .completed),
        Transition(.processing, .cancel, .cancelled),
        Transition(.processing, .fail(.deviceDisconnected), .failed(.deviceDisconnected)),
        Transition(.completed, .reset, .idle),
        Transition(.cancelled, .reset, .idle),
        Transition(.failed(.interrupted), .reset, .idle),
        Transition(.completed, .activate, .preparing),
        Transition(.cancelled, .activate, .preparing),
        Transition(.failed(.interrupted), .activate, .preparing),
    ]

    @Test(arguments: valid)
    func allowsEveryDocumentedTransition(_ transition: Transition) {
        #expect(RecorderStateMachine.transition(from: transition.from, on: transition.event) == transition.expected)
    }

    @Test func rejectsEveryOtherTransition() {
        for state in Self.allStates {
            for event in Self.allEvents
            where !Self.valid.contains(where: { $0.from == state && $0.event == event }) {
                #expect(
                    RecorderStateMachine.transition(from: state, on: event) == nil,
                    "\(state) + \(event) should be rejected")
            }
        }
    }

    @Test func rejectedEventLeavesStateUnchanged() {
        var machine = RecorderStateMachine()
        machine.handle(.activate)
        machine.handle(.captureStarted)

        let accepted = machine.handle(.activate)  // no overlapping session
        #expect(!accepted)
        #expect(machine.state == .recording)
    }

    @Test func fullHappyPath() {
        var machine = RecorderStateMachine()
        for event in [RecorderEvent.activate, .captureStarted, .stopRequested, .captureFinished, .processingFinished] {
            let accepted = machine.handle(event)
            #expect(accepted)
        }
        #expect(machine.state == .completed)
        let reset = machine.handle(.reset)
        #expect(reset)
        #expect(machine.state == .idle)
    }

    @Test func capturingStatesAreTheOnesThatMayUseTheMicrophone() {
        #expect(Self.allStates.filter(\.isCapturing) == [.preparing, .recording, .stopping])
        #expect(Self.allStates.filter(\.isFinished) == [.completed, .cancelled, .failed(.interrupted)])
    }
}
