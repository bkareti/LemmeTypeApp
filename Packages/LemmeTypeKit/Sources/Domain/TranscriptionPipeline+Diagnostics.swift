/// Session metrics of ``TranscriptionPipeline`` (ADR 0008).
extension TranscriptionPipeline {
    /// Session metrics: outcome, engine, durations, error category — no audio
    /// or text. `processingSeconds` runs from capture stop to delivery (the
    /// latency the user feels); `recognitionSeconds` is inference alone.
    func record(_ run: Run, session: DictationSession, elapsed: Duration) {
        let seconds = Self.seconds(elapsed)
        switch run.outcome {
        case .delivered(let method):
            diagnostics.record(
                .recognition, "session.delivered",
                [
                    "method": .id(method.rawValue), "mode": .id(session.mode.rawValue),
                    "engine": .id(run.engine?.rawValue ?? "none"), "context": .id(session.contextIdentifier),
                    "purpose": .id(session.purpose.rawValue),
                    "language": .id(Self.languageIdentifier(session.language)),
                    "task": .id(Self.task(for: session).rawValue), "output": .id(session.speechOutput.rawValue),
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
                    "language": .id(Self.languageIdentifier(session.language)),
                    "task": .id(Self.task(for: session).rawValue),
                    "audioSeconds": .seconds(session.audio.duration), "processingSeconds": .seconds(seconds),
                ])
        case .review(let review, let engine):
            diagnostics.record(
                .recognition, "session.review",
                [
                    "style": .id(review.style.identifier), "rewritten": .flag(review.isRewritten),
                    "notice": .id(review.notice?.identifier ?? "none"),
                    "engine": .id(engine?.rawValue ?? "none"), "mode": .id(session.mode.rawValue),
                    "language": .id(Self.languageIdentifier(session.language)),
                    "rewriteSeconds": .seconds(run.rewriting.map(Self.seconds) ?? 0),
                    "audioSeconds": .seconds(session.audio.duration), "processingSeconds": .seconds(seconds),
                ])
        case .cancelled:
            diagnostics.record(.recognition, "session.cancelled", ["processingSeconds": .seconds(seconds)])
        }
    }

    /// `auto` or a lowercase language code: safe for diagnostics.
    static func languageIdentifier(_ language: String) -> String {
        SpokenLanguages.isAutomatic(language) ? language : SpokenLanguages.code(of: language)
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
