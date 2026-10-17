import Foundation

/// The production ``DictationProcessing``: engine selection, recognition
/// through ``RecognitionRunner``, writing mode, and delivery. Uses only Domain
/// protocols, so it runs unchanged against fakes in tests.
public actor TranscriptionPipeline: DictationProcessing {
    private let engines: [any SpeechRecognitionEngine]
    let write: @Sendable (String, WritingMode) -> String
    let format: @Sendable (String, WritingMode, CursorContext) -> String
    private let delivery: any TextDelivering
    private let rewriter: (any TextRewriting)?
    private let copier: (any TextCopying)?
    private let diagnostics: any DiagnosticsRecording

    /// `engines` are in recommendation order (Automatic picks the first ready
    /// one); each session carries the user's ``EnginePreference``; `write`
    /// applies a writing mode to recognised text; `format` fits it into the
    /// cursor context, when the session has one (E3-S3); `rewriter` runs
    /// voice-editing sessions (E3-S5), which are refused without one;
    /// `copier` serves modes whose output is Copy only (E4-S5).
    public init(
        engines: [any SpeechRecognitionEngine],
        write: @escaping @Sendable (String, WritingMode) -> String = TextCleaner.write,
        format: @escaping @Sendable (String, WritingMode, CursorContext) -> String = ContextFormatter.format,
        delivery: any TextDelivering,
        rewriter: (any TextRewriting)? = nil,
        copier: (any TextCopying)? = nil,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.copier = copier
        self.engines = engines
        self.write = write
        self.format = format
        self.delivery = delivery
        self.rewriter = rewriter
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
    struct Run {
        var outcome: DictationOutcome
        var engine: RecognitionEngineID?
        var recognition: Duration?
        var rewriting: Duration?
        /// Vocabulary and replacement changes applied (E4-S2).
        var personalizations = 0
        /// The utterance was a snippet trigger (E4-S3).
        var usedSnippet = false
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
                engine, RecognitionRequest(audio: session.audio, language: session.language, hints: hints(for: session))
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
        var run = Run(outcome: .cancelled, engine: id, recognition: ContinuousClock.now - recognitionStart)
        guard let text = await text(from: transcript, session: session, run: &run, updates: updates) else {
            return run
        }
        if Task.isCancelled { return run }
        // Delivering nothing would replace a selection with nothing.
        guard text.contains(where: { !$0.isWhitespace }) else {
            run.outcome = Self.attention(.recognitionFailed(.noSpeechDetected), engine: id)
            return run
        }
        updates(.phase(.delivering))
        run.outcome = await deliver(text, session: session, engine: id)
        return run
    }

    /// The text to deliver: the written transcript, or (voice editing) the
    /// rewritten selection. `nil` after setting `run.outcome` on failure.
    private func text(
        from transcript: Transcript, session: DictationSession, run: inout Run,
        updates: @escaping @Sendable (ProcessingUpdate) -> Void
    ) async -> String? {
        switch session.purpose {
        case .dictation:
            updates(.phase(.writing))
            return written(transcript.text, session: session, run: &run)
        case .editing:
            updates(.phase(.rewriting))
            let rewriteStart = ContinuousClock.now
            let result = await rewrite(instruction: transcript.text, session: session)
            run.rewriting = ContinuousClock.now - rewriteStart
            switch result {
            case .success(let edited):
                return edited
            case .failure(let failure):
                run.outcome = Task.isCancelled ? .cancelled : Self.attention(failure.issue, engine: run.engine)
                return nil
            }
        }
    }

    private struct EditingFailure: Error {
        let issue: DictationIssue
    }

    /// Applies the spoken instruction to the captured selection (E3-S5).
    private func rewrite(instruction spoken: String, session: DictationSession) async
        -> Result<String, EditingFailure>
    {
        guard let selected = session.editingContext?.selectedText else {
            return .failure(EditingFailure(issue: .editingUnavailable(.noSelection)))
        }
        let instruction = TextCleaner.normalizeWhitespace(spoken)
        guard instruction.contains(where: { !$0.isWhitespace }) else {
            return .failure(EditingFailure(issue: .recognitionFailed(.noSpeechDetected)))
        }
        guard let rewriter else { return .failure(EditingFailure(issue: .rewriterUnavailable(.unavailable))) }
        do {
            let edited = try await TextRewritingRunner().run(
                rewriter, RewriteRequest(instruction: instruction, text: selected, language: session.language))
            return .success(edited)
        } catch .unavailable(let availability) {
            return .failure(EditingFailure(issue: .rewriterUnavailable(availability)))
        } catch {
            return .failure(EditingFailure(issue: .rewriteFailed(error)))
        }
    }

    private static func attention(_ issue: DictationIssue, engine: RecognitionEngineID?) -> DictationOutcome {
        .needsAttention(issue, engine: engine, alternatives: [], transcript: nil)
    }

    public func editingIssue(for target: ActivationTarget?, language: String) async -> DictationIssue? {
        switch target?.context {
        case .captured(let context, .editing) where context.selectedText != nil:
            break
        case .blocked(let reason, .editing):
            return .editingUnavailable(reason)
        default:
            return .editingUnavailable(target == nil ? .unreadable : .noSelection)
        }
        guard let rewriter else { return .rewriterUnavailable(.unavailable) }
        let availability = await rewriter.availability(language: language)
        return availability.isReady ? nil : .rewriterUnavailable(availability)
    }

    private func deliver(_ text: String, session: DictationSession, engine: RecognitionEngineID?) async
        -> DictationOutcome
    {
        // Copy only: the target app is never touched (E4-S5).
        if session.purpose == .dictation, session.dictationMode.output == .copy, let copier {
            await copier.copy(text)
            return .delivered(.copied)
        }
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
                    "purpose": .id(session.purpose.rawValue),
                    "dictationMode": .id(session.dictationMode.id.diagnosticIdentifier),
                    "modeSource": .id(session.modeSource.rawValue),
                    "audioSeconds": .seconds(session.audio.duration), "processingSeconds": .seconds(seconds),
                    "recognitionSeconds": .seconds(run.recognition.map(Self.seconds) ?? 0),
                    "rewriteSeconds": .seconds(run.rewriting.map(Self.seconds) ?? 0),
                    "personalizations": .count(run.personalizations), "snippet": .flag(run.usedSnippet),
                ])
        case .needsAttention(let issue, let engine, _, _):
            diagnostics.record(
                .recognition, "session.needs-attention",
                [
                    "issue": .id(issue.identifier), "engine": .id(engine?.rawValue ?? "none"),
                    "mode": .id(session.mode.rawValue), "purpose": .id(session.purpose.rawValue),
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
