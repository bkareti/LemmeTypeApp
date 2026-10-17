import Foundation

/// The production ``DictationProcessing``: engine selection, recognition
/// through ``RecognitionRunner``, writing mode, and delivery. Uses only Domain
/// protocols, so it runs unchanged against fakes in tests.
public actor TranscriptionPipeline: DictationProcessing {
    private let engines: [any SpeechRecognitionEngine]
    private let write: @Sendable (String, WritingMode) -> String
    private let format: @Sendable (String, WritingMode, CursorContext) -> String
    private let delivery: any TextDelivering
    private let diagnostics: any DiagnosticsRecording

    /// `engines` are in recommendation order (Automatic picks the first ready
    /// one); each session carries the user's ``EnginePreference``; `write`
    /// applies a writing mode to recognised text; `format` fits it into the
    /// cursor context, when the session has one (E3-S3).
    public init(
        engines: [any SpeechRecognitionEngine],
        write: @escaping @Sendable (String, WritingMode) -> String = TextCleaner.write,
        format: @escaping @Sendable (String, WritingMode, CursorContext) -> String = ContextFormatter.format,
        delivery: any TextDelivering,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.engines = engines
        self.write = write
        self.format = format
        self.delivery = delivery
        self.diagnostics = diagnostics
    }

    public func process(
        _ session: DictationSession,
        updates: @escaping @Sendable (ProcessingUpdate) -> Void
    ) async -> DictationOutcome {
        let start = ContinuousClock.now
        updates(.phase(.preparingEngine))
        let run = await run(session, updates: updates)
        let outcome = run.outcome
        record(run, session: session, elapsed: ContinuousClock.now - start)
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

    /// The outcome, the engine used, and how long recognition took, if it ran.
    private struct Run {
        let outcome: DictationOutcome
        var engine: RecognitionEngineID?
        var recognition: Duration?
    }

    private func run(
        _ session: DictationSession,
        updates: @escaping @Sendable (ProcessingUpdate) -> Void
    ) async -> Run {
        let engine: any SpeechRecognitionEngine
        switch await select(for: session) {
        case .success(let chosen):
            engine = chosen
        case .failure(let failure):
            return Run(outcome: failure.outcome)
        }
        let id = engine.descriptor.id
        if Task.isCancelled { return Run(outcome: .cancelled, engine: id) }
        updates(.phase(.recognizing))
        let recognitionStart = ContinuousClock.now
        let transcript: Transcript
        do {
            transcript = try await RecognitionRunner().run(
                engine, RecognitionRequest(audio: session.audio, language: session.language)
            ) { update in
                if case .progress(let fraction) = update { updates(.progress(fraction)) }
            }
        } catch .cancelled {
            return Run(outcome: .cancelled, engine: id)
        } catch {
            let alternatives = await readyEngines(excluding: engine.descriptor.id)
            return Run(
                outcome: .needsAttention(
                    .recognitionFailed(error), engine: id, alternatives: alternatives, transcript: nil),
                engine: id, recognition: ContinuousClock.now - recognitionStart)
        }
        let recognition = ContinuousClock.now - recognitionStart
        updates(.phase(.writing))
        var text = write(transcript.text, session.mode)
        if let context = session.formattingContext, text.contains(where: { !$0.isWhitespace }) {
            text = format(text, session.mode, context)
        }
        if Task.isCancelled { return Run(outcome: .cancelled, engine: id, recognition: recognition) }
        // Delivering nothing would replace a selection with nothing.
        guard text.contains(where: { !$0.isWhitespace }) else {
            return Run(
                outcome: .needsAttention(
                    .recognitionFailed(.noSpeechDetected), engine: id, alternatives: [], transcript: nil),
                engine: id, recognition: recognition)
        }
        updates(.phase(.delivering))
        return Run(outcome: await deliver(text, session: session, engine: id), engine: id, recognition: recognition)
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
        let preference = session.enginePreference
        switch EngineSelector.choose(
            preferred: preference.selected, fallsBackAutomatically: preference.fallsBackAutomatically,
            candidates: candidates)
        {
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

    /// Session metrics: outcome, engine, durations, error category — no audio
    /// or text. `processingSeconds` runs from capture stop to delivery (the
    /// latency the user feels); `recognitionSeconds` is inference alone.
    private func record(_ run: Run, session: DictationSession, elapsed: Duration) {
        let seconds = Self.seconds(elapsed)
        switch run.outcome {
        case .delivered(let method):
            diagnostics.record(
                .recognition, "session.delivered",
                [
                    "method": .id(method.rawValue), "mode": .id(session.mode.rawValue),
                    "engine": .id(run.engine?.rawValue ?? "none"), "context": .id(session.contextIdentifier),
                    "audioSeconds": .seconds(session.audio.duration), "processingSeconds": .seconds(seconds),
                    "recognitionSeconds": .seconds(run.recognition.map(Self.seconds) ?? 0),
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

extension TranscriptionPipeline {
    fileprivate static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

private struct SelectionFailure: Error {
    let outcome: DictationOutcome
}
