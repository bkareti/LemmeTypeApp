/// The language and translation steps of ``TranscriptionPipeline`` (E9-S2 … E9-S5,
/// docs/decisions/0023-multilingual-dictation.md).
extension TranscriptionPipeline {
    /// Dictation follows the session's language and output; a spoken editing
    /// instruction is only transcribed (E9-S4).
    static func task(for session: DictationSession) -> RecognitionTask {
        session.purpose == .dictation
            ? .required(for: session.language, output: session.speechOutput) : .transcribe
    }

    /// Whether the text is a translation the user must review: translation was
    /// asked for and the speech was not already English.
    static func wasTranslated(_ transcript: Transcript, task: RecognitionTask, session: DictationSession) -> Bool {
        task == .translateToEnglish
            && !SpokenLanguages.isEnglish(transcript.spokenLanguage ?? session.language)
    }

    public func languageIssue(language: String, output: SpeechOutput, enginePreference: EnginePreference) async
        -> DictationIssue?
    {
        guard LanguageReadiness.isBeyondEnglishDictation(language: language, output: output) else { return nil }
        let readiness = await LanguageReadiness.evaluate(
            language: language, output: output, engines: engines, preference: enginePreference,
            hardware: hardware)
        return readiness.isReady ? nil : .languageUnavailable(readiness)
    }

    /// The outcome that holds `text` for the user instead of delivering it: a
    /// rewrite (E10-S4) or a translation (E9-S5) is read before it goes anywhere.
    static func heldForReview(
        _ run: Run, transcript: Transcript, task: RecognitionTask, session: DictationSession, text: String
    ) -> DictationOutcome? {
        if let review = run.review { return .review(review, engine: run.engine) }
        guard session.purpose == .dictation, wasTranslated(transcript, task: task, session: session) else {
            return nil
        }
        return .needsAttention(.reviewTranslation, engine: run.engine, alternatives: [], transcript: text)
    }
}
