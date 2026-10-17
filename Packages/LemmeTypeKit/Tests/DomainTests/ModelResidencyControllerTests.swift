import Domain
import Synchronization
import TestSupport
import Testing

/// E5-S4 and E5-S6: models load lazily, warm up while the user speaks, and
/// unload after the idle period or under memory pressure — never mid-session.
struct ModelResidencyControllerTests {
    final class PlanBox: Sendable {
        private let storage: Mutex<PerformancePlan>
        init(_ plan: PerformancePlan) { storage = Mutex(plan) }
        var plan: PerformancePlan {
            get { storage.withLock { $0 } }
            set { storage.withLock { $0 = newValue } }
        }
    }

    static func plan(
        _ profile: PerformanceProfile = .balanced, idle: IdleUnloadPolicy = .after(minutes: 5)
    ) -> PerformancePlan {
        PerformancePlan.make(profile: profile, conditions: .nominal, idleUnload: idle, processors: 8)
    }

    private func make(
        _ engines: [FakeRecognitionEngine], plan: PerformancePlan = Self.plan(), clock: ManualClock = ManualClock()
    ) -> (ModelResidencyController, PlanBox) {
        let box = PlanBox(plan)
        return (ModelResidencyController(engines: engines, plan: { box.plan }, clock: clock), box)
    }

    @Test func nothingLoadsUntilASessionStarts() async {
        let engine = FakeRecognitionEngine(id: .whisper)
        _ = make([engine])
        #expect(engine.prepareCount == 0)
    }

    @Test func warmUpPreparesThePreferredOrFirstReadyEngineOnce() async {
        let apple = FakeRecognitionEngine(id: .appleSpeech, availability: .permissionUnavailable)
        let whisper = FakeRecognitionEngine(id: .whisper)
        let (residency, _) = make([apple, whisper])
        await residency.sessionBusy()
        await residency.warmUp(preferred: nil, language: "en-US")
        await residency.warmUp(preferred: nil, language: "en-US")
        await residency.settle()
        #expect(apple.prepareCount == 0)
        #expect(whisper.prepareCount == 1)

        let (chosen, _) = make([apple, whisper])
        await chosen.warmUp(preferred: .appleSpeech, language: "en-US")  // not ready: nothing to warm
        await chosen.settle()
        #expect(apple.prepareCount == 0)
    }

    @Test func lowPowerNeverWarmsUp() async {
        let engine = FakeRecognitionEngine(id: .whisper)
        let (residency, _) = make([engine], plan: Self.plan(.lowPower))
        await residency.warmUp(preferred: nil, language: "en-US")
        await residency.settle()
        #expect(engine.prepareCount == 0)
    }

    @Test func idlePeriodUnloadsOnceAndANewSessionResetsTheTimer() async {
        let engine = FakeRecognitionEngine(id: .whisper)
        let clock = ManualClock()
        let (residency, _) = make([engine], clock: clock)

        await residency.sessionBusy()
        await residency.sessionIdle()
        await clock.waitForSleepers()
        clock.advance(by: .seconds(240))
        await residency.sessionBusy()  // a session before the five minutes are up
        #expect(engine.unloadCount == 0)
        await residency.sessionIdle()
        await clock.waitForSleepers()
        clock.advance(by: .seconds(240))
        await Self.yield()
        #expect(engine.unloadCount == 0)
        clock.advance(by: .seconds(60))
        await Self.waitFor { engine.unloadCount == 1 }
        #expect(engine.unloadCount == 1)
        clock.advance(by: .seconds(600))
        await Self.yield()
        #expect(engine.unloadCount == 1)
    }

    @Test func neverKeepsModelsUntilMemoryPressure() async {
        let engine = FakeRecognitionEngine(id: .whisper)
        let clock = ManualClock()
        let (residency, _) = make([engine], plan: Self.plan(idle: .never), clock: clock)
        await residency.sessionBusy()
        await residency.sessionIdle()
        await Self.yield()
        #expect(clock.sleeperCount == 0)
        await residency.memoryPressure()
        #expect(engine.unloadCount == 1)
    }

    @Test func memoryPressureDuringASessionWaitsForItToEnd() async {
        let engine = FakeRecognitionEngine(id: .whisper)
        let (residency, _) = make([engine])
        await residency.sessionBusy()
        await residency.memoryPressure()
        #expect(engine.unloadCount == 0)  // recognition keeps its model
        await residency.sessionIdle()
        #expect(engine.unloadCount == 1)
    }

    @Test func memoryPressureWhileIdleUnloadsAtOnce() async {
        let engine = FakeRecognitionEngine(id: .whisper)
        let (residency, _) = make([engine])
        await residency.memoryPressure()
        #expect(engine.unloadCount == 1)
    }

    static func yield() async {
        for _ in 0..<50 { await Task.yield() }
    }

    static func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() { await Task.yield() }
    }
}
