import Domain
import Testing

struct ActivationInterpreterTests {
    @Test func pushToTalkStartsOnPressAndStopsOnRelease() {
        var interpreter = ActivationInterpreter(mode: .pushToTalk)

        #expect(interpreter.handle(ShortcutEvent(.pressed, at: 0)) == .start)
        #expect(interpreter.isSessionActive)
        #expect(interpreter.handle(ShortcutEvent(.released, at: 1)) == .stop)
        #expect(!interpreter.isSessionActive)
    }

    @Test func toggleStartsOnFirstPressAndStopsOnSecond() {
        var interpreter = ActivationInterpreter(mode: .toggle)

        #expect(interpreter.handle(ShortcutEvent(.pressed, at: 0)) == .start)
        #expect(interpreter.handle(ShortcutEvent(.released, at: 0.1)) == .ignore)
        #expect(interpreter.isSessionActive)
        #expect(interpreter.handle(ShortcutEvent(.pressed, at: 2)) == .stop)
        #expect(interpreter.handle(ShortcutEvent(.released, at: 2.1)) == .ignore)
        #expect(!interpreter.isSessionActive)
    }

    @Test(arguments: ActivationMode.allCases)
    func keyRepeatWhileHeldNeverStartsASecondSession(mode: ActivationMode) {
        var interpreter = ActivationInterpreter(mode: mode)

        let decisions = [0, 0.5, 0.6, 0.7].map { interpreter.handle(ShortcutEvent(.pressed, at: $0)) }

        #expect(decisions == [.start, .ignore, .ignore, .ignore])
    }

    @Test func bouncingToggleWithinDebounceIntervalIsIgnored() {
        var interpreter = ActivationInterpreter(mode: .toggle)

        #expect(interpreter.handle(ShortcutEvent(.pressed, at: 10)) == .start)
        #expect(interpreter.handle(ShortcutEvent(.released, at: 10.02)) == .ignore)
        #expect(interpreter.handle(ShortcutEvent(.pressed, at: 10.05)) == .ignore)
        #expect(interpreter.isSessionActive)
    }

    @Test func bouncingPushToTalkDoesNotOverlapSessions() {
        var interpreter = ActivationInterpreter(mode: .pushToTalk)
        var active = 0
        var maxActive = 0
        let events: [ShortcutEvent] = [
            .init(.pressed, at: 0), .init(.released, at: 0.01), .init(.pressed, at: 0.02),
            .init(.released, at: 0.03), .init(.pressed, at: 1), .init(.released, at: 2),
        ]

        for event in events {
            switch interpreter.handle(event) {
            case .start: active += 1
            case .stop: active -= 1
            case .ignore: break
            }
            maxActive = max(maxActive, active)
        }

        #expect(maxActive == 1)
        #expect(active == 0)
    }

    @Test func releaseWithoutPressIsIgnored() {
        var interpreter = ActivationInterpreter(mode: .pushToTalk)

        #expect(interpreter.handle(ShortcutEvent(.released, at: 0)) == .ignore)
    }

    @Test func endedSessionLetsTheNextPressStartAgain() {
        var interpreter = ActivationInterpreter(mode: .toggle)
        _ = interpreter.handle(ShortcutEvent(.pressed, at: 0))
        _ = interpreter.handle(ShortcutEvent(.released, at: 0.1))

        interpreter.sessionEnded()

        #expect(interpreter.handle(ShortcutEvent(.pressed, at: 5)) == .start)
    }

    @Test func pushToTalkReleaseAfterCancelDoesNotStop() {
        var interpreter = ActivationInterpreter(mode: .pushToTalk)
        _ = interpreter.handle(ShortcutEvent(.pressed, at: 0))

        interpreter.sessionEnded()

        #expect(interpreter.handle(ShortcutEvent(.released, at: 1)) == .ignore)
        #expect(interpreter.handle(ShortcutEvent(.pressed, at: 2)) == .start)
    }
}
