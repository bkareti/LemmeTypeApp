/// The opt-in tone, format, and length step of ``TranscriptionPipeline``
/// (E10-S3, docs/decisions/0024-tone-and-style-rewriting.md).
extension TranscriptionPipeline {
    /// The dictation text: written, then (when the mode has a style) rewritten
    /// on this Mac. A style always ends in a review, so `run.review` is set and
    /// nothing is delivered until the user chooses.
    func styled(
        _ transcript: Transcript, session: DictationSession, run: inout Run,
        updates: @escaping @Sendable (ProcessingUpdate) -> Void
    ) async -> String {
        let language = transcript.language
        let before = writtenBeforeStyle(transcript.text, language: language, session: session, run: &run)
        let style = session.dictationMode.effectiveStyle
        guard !before.isFinal else { return before.text }
        guard !style.isNone else { return finished(before.text, language: language, session: session) }

        updates(.phase(.rewriting))
        let original = finished(before.text, language: language, session: session)
        let start = ContinuousClock.now
        let result = await applyStyle(style, to: before.text, language: language)
        run.rewriting = ContinuousClock.now - start
        run.review = review(of: result, original: original, language: language, style: style, session: session)
        return run.review?.text ?? original
    }

    /// Rewrites `original` again in the session's style, without recognising
    /// the audio again (E10-S4). The result is a review, like the first one.
    public func regenerate(
        _ original: String, for session: DictationSession,
        updates: @escaping @Sendable (ProcessingUpdate) -> Void
    ) async -> DictationOutcome {
        let style = session.dictationMode.effectiveStyle
        guard !style.isNone else { return .cancelled }
        updates(.phase(.rewriting))
        let language = session.language
        let start = ContinuousClock.now
        let result = await applyStyle(style, to: original, language: Self.rewriteLanguage(for: session))
        if Task.isCancelled { return .cancelled }
        let review = review(
            of: result, original: original, language: Self.rewriteLanguage(for: session), style: style,
            session: session)
        diagnostics.record(
            .recognition, "session.regenerated",
            [
                "style": .id(style.identifier), "rewritten": .flag(review.isRewritten),
                "rewriteSeconds": .seconds(Self.seconds(ContinuousClock.now - start)),
                "language": .id(Self.languageIdentifier(language)),
            ])
        return .review(review, engine: session.engine)
    }

    /// The language of the text that is rewritten: English after a translation.
    static func rewriteLanguage(for session: DictationSession) -> String {
        session.speechOutput == .english ? "en" : SpokenLanguages.editingLanguage(for: session.language)
    }

    enum StyleResult {
        case rewritten(String)
        case kept(RewriteNotice)
    }

    /// Runs the model with the fixed instruction and keeps its answer only if
    /// it preserved what was said.
    func applyStyle(_ style: StyleOptions, to text: String, language: String) async -> StyleResult {
        guard let instruction = StyleInstruction.make(style) else { return .kept(.failed) }
        guard let rewriter else { return .kept(.unavailable(.unavailable)) }
        let passage = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let rewritten = try await TextRewritingRunner().run(
                rewriter, RewriteRequest(instruction: instruction, text: passage, language: language))
            let violations = PreservationChecker.violations(original: passage, rewritten: rewritten)
            return violations.isEmpty ? .rewritten(rewritten) : .kept(.meaningChanged(violations))
        } catch .unavailable(let availability) {
            return .kept(.unavailable(availability))
        } catch .refused {
            return .kept(.refused)
        } catch .tooLong {
            return .kept(.tooLong)
        } catch {
            return .kept(.failed)
        }
    }

    private func review(
        of result: StyleResult, original: String, language: String, style: StyleOptions, session: DictationSession
    ) -> DictationReview {
        switch result {
        case .rewritten(let rewritten):
            DictationReview(
                text: finished(rewritten, language: language, session: session), original: original,
                language: language, style: style)
        case .kept(let notice):
            DictationReview(
                text: original, original: original, language: language, style: style, notice: notice)
        }
    }
}
