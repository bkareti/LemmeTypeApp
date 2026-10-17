import Foundation

/// Keeps speech models in memory only while useful (E5-S4, E5-S6).
///
/// The recorder marks when a session is busy (recording or processing) and
/// when it ends; after the plan's idle period with no busy session, every
/// engine is unloaded. Memory pressure unloads at once, or right after the
/// busy session. Models are never unloaded while a session is busy.
public protocol ModelResidencyManaging: Sendable {
    /// A session started recording or processing. Cancels a pending unload.
    func sessionBusy() async
    /// Starts loading the engine the session will most likely use, if the plan allows.
    func warmUp(preferred: RecognitionEngineID?, language: String) async
    /// The session finished; the idle period starts.
    func sessionIdle() async
    /// The system is short of memory.
    func memoryPressure() async
}

/// Why models were unloaded. Raw values are diagnostics identifiers.
public enum UnloadReason: String, Sendable {
    case idle
    case memoryPressure = "memory-pressure"
}

public actor ModelResidencyController: ModelResidencyManaging {
    private let engines: [any SpeechRecognitionEngine]
    private let plan: @Sendable () -> PerformancePlan
    private let clock: any Clock<Duration>
    private let diagnostics: any DiagnosticsRecording
    private var isBusy = false
    private var unloadsWhenIdle = false
    private var idleTask: Task<Void, Never>?
    private var warmUpTask: Task<Void, Never>?
    private var generation = 0

    /// `engines` in recommendation order (warm-up picks like Automatic);
    /// `plan` is read at every decision so profile changes apply at once.
    public init(
        engines: [any SpeechRecognitionEngine],
        plan: @escaping @Sendable () -> PerformancePlan,
        clock: any Clock<Duration> = ContinuousClock(),
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.engines = engines
        self.plan = plan
        self.clock = clock
        self.diagnostics = diagnostics
    }

    public func sessionBusy() {
        isBusy = true
        generation += 1
        idleTask?.cancel()
        idleTask = nil
    }

    public func warmUp(preferred: RecognitionEngineID?, language: String) async {
        guard plan().warmsUpDuringRecording, warmUpTask == nil else { return }
        guard let engine = await engineToWarm(preferred: preferred, language: language) else { return }
        let id = engine.descriptor.id
        diagnostics.record(.models, "model.warm-up", ["engine": .id(id.rawValue)])
        warmUpTask = Task { [weak self] in
            // A failed warm-up is harmless: recognition loads (and reports) again.
            try? await engine.prepare()
            await self?.warmUpFinished()
        }
    }

    public func sessionIdle() async {
        isBusy = false
        if unloadsWhenIdle {
            unloadsWhenIdle = false
            await unloadAll(.memoryPressure)
            return
        }
        scheduleIdleUnload()
    }

    public func memoryPressure() async {
        guard !isBusy else {
            unloadsWhenIdle = true  // never pull a model out from under recognition
            return
        }
        idleTask?.cancel()
        idleTask = nil
        await unloadAll(.memoryPressure)
    }

    /// Waits for a running warm-up. For tests.
    public func settle() async {
        await warmUpTask?.value
    }

    // MARK: Steps

    private func warmUpFinished() {
        warmUpTask = nil
    }

    private func engineToWarm(preferred: RecognitionEngineID?, language: String) async
        -> (any SpeechRecognitionEngine)?
    {
        if let preferred, let engine = engines.first(where: { $0.descriptor.id == preferred }) {
            return await engine.availability().isReady ? engine : nil
        }
        for engine in engines where engine.descriptor.supports(language: language) {
            if await engine.availability().isReady { return engine }
        }
        return nil
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        guard let duration = plan().idleUnload.duration else {
            idleTask = nil
            return
        }
        let clock = self.clock
        let scheduled = generation
        idleTask = Task { [weak self] in
            do {
                try await clock.sleep(for: duration)
            } catch {
                return
            }
            await self?.idleExpired(scheduled)
        }
    }

    private func idleExpired(_ scheduled: Int) async {
        guard !isBusy, scheduled == generation else { return }
        idleTask = nil
        await unloadAll(.idle)
    }

    private func unloadAll(_ reason: UnloadReason) async {
        warmUpTask?.cancel()
        warmUpTask = nil
        for engine in engines {
            await engine.unload()
        }
        diagnostics.record(.models, "model.unloaded", ["reason": .id(reason.rawValue)])
    }
}
