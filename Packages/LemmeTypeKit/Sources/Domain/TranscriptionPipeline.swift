import Foundation

/// The production ``DictationProcessing``: engine selection, recognition
/// through ``RecognitionRunner``, writing mode, and delivery. Uses only Domain
/// protocols, so it runs unchanged against fakes in tests.
public actor TranscriptionPipeline: DictationProcessing {
    private let engines: [any SpeechRecognitionEngine]
    private let preferredEngine: @Sendable () -> RecognitionEngineID?
    private let write: @Sendable (String, WritingMode) -> String
    private let delivery: any TextDelivering
    private let diagnostics: any DiagnosticsRecording

    /// `engines` are in recommendation order (Automatic picks the first ready
    /// one); `preferredEngine` is read once per session (`nil` = Automatic);
    /// `write` applies a writing mode to recognised text.
    public init(
        engines: [any SpeechRecognitionEngine],
        preferredEngine: @escaping @Sendable () -> RecognitionEngineID?,
        write: @escaping @Sendable (String, WritingMode) -> String = TextCleaner.write,
        delivery: any TextDelivering,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.engines = engines
        self.preferredEngine = preferredEngine
        self.write = write
        self.delivery = delivery
        self.diagnostics = diagnostics
    }

    public func process(
        _ session: DictationSession,
        updates: @escaping @Sendable (ProcessingUpdate) -> Void
    ) async -> DictationOutcome {
        let start = ContinuousClock.now
        updates(.phase(.preparingEngine))
        let outcome = await run(session, updates: updates)
        record(outcome, session: session, elapsed: ContinuousClock.now - start)
        if case .delivered = outcome {
            session.discardAudio()
        }
        return outcome
    }

    public func deliver(_ transcript: String, for session: DictationSession) async -> DictationOutcome {
        let outcome = await deliver(transcript, session: session, engine: session.engine)
        if case .delivered = outcome {
            session.discardAudio()
        }
        return outcome
    }

    // MARK: Steps

    private func run(
        _ session: DictationSession,
        updates: @escaping @Sendable (ProcessingUpdate) -> Void
    ) async -> DictationOutcome {
        let engine: any SpeechRecognitionEngine
        switch await select(for: session) {
        case .success(let chosen):
            engine = chosen
        case .failure(let failure):
            return failure.outcome
        }
        if Task.isCancelled { return .cancelled }
        updates(.phase(.recognizing))
        let transcript: Transcript
        do {
            transcript = try await RecognitionRunner().run(
                engine, RecognitionRequest(audio: session.audio, language: session.language)
            ) { update in
                if case .progress(let fraction) = update { updates(.progress(fraction)) }
            }
        } catch .cancelled {
            return .cancelled
        } catch {
            return .needsAttention(
                .recognitionFailed(error), engine: engine.descriptor.id,
                alternatives: await readyEngines(excluding: engine.descriptor.id), transcript: nil)
        }
        updates(.phase(.writing))
        let text = write(transcript.text, session.mode)
        if Task.isCancelled { return .cancelled }
        updates(.phase(.delivering))
        return await deliver(text, session: session, engine: engine.descriptor.id)
    }

    private func deliver(_ text: String, session: DictationSession, engine: RecognitionEngineID?) async
        -> DictationOutcome
    {
        switch await delivery.deliver(text, to: session.target) {
        case .delivered(let method):
            return .delivered(method)
        case .problem(let problem):
            return .needsAttention(.deliveryFailed(problem), engine: engine, alternatives: [], transcript: text)
        }
    }

    private func select(for session: DictationSession) async -> Result<any SpeechRecognitionEngine, SelectionFailure> {
        if let id = session.engine, let engine = engines.first(where: { $0.descriptor.id == id }) {
            return .success(engine)
        }
        var candidates: [(id: RecognitionEngineID, availability: EngineAvailability)] = []
        for engine in engines where engine.descriptor.supports(language: session.language) {
            candidates.append((engine.descriptor.id, await engine.availability()))
        }
        switch EngineSelector.choose(preferred: preferredEngine(), candidates: candidates) {
        case .engine(let id):
            guard let engine = engines.first(where: { $0.descriptor.id == id }) else {
                return .failure(SelectionFailure(outcome: Self.noEngine))
            }
            return .success(engine)
        case .unavailable(let id, let availability, let alternatives):
            return .failure(
                SelectionFailure(
                    outcome: .needsAttention(
                        .engineUnavailable(id, availability), engine: id, alternatives: alternatives,
                        transcript: nil)))
        case .noneAvailable:
            return .failure(SelectionFailure(outcome: Self.noEngine))
        }
    }

    private static let noEngine = DictationOutcome.needsAttention(
        .noEngineAvailable, engine: nil, alternatives: [], transcript: nil)

    private func readyEngines(excluding id: RecognitionEngineID) async -> [RecognitionEngineID] {
        var ready: [RecognitionEngineID] = []
        for engine in engines where engine.descriptor.id != id {
            if await engine.availability().isReady {
                ready.append(engine.descriptor.id)
            }
        }
        return ready
    }

    /// Session metrics: outcome, engine, durations, error category — no audio or text.
    private func record(_ outcome: DictationOutcome, session: DictationSession, elapsed: Duration) {
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        switch outcome {
        case .delivered(let method):
            diagnostics.record(
                .recognition, "session.delivered",
                [
                    "method": .id(method.rawValue), "mode": .id(session.mode.rawValue),
                    "audioSeconds": .seconds(session.audio.duration),
                    "processingSeconds": .seconds(seconds),
                ])
        case .needsAttention(let issue, let engine, _, _):
            diagnostics.record(
                .recognition, "session.needs-attention",
                [
                    "issue": .id(issue.identifier), "engine": .id(engine?.rawValue ?? "none"),
                    "mode": .id(session.mode.rawValue),
                    "audioSeconds": .seconds(session.audio.duration), "processingSeconds": .seconds(seconds),
                ])
        case .cancelled:
            diagnostics.record(.recognition, "session.cancelled", ["processingSeconds": .seconds(seconds)])
        }
    }
}

private struct SelectionFailure: Error {
    let outcome: DictationOutcome
}
