/// The dictation text steps of ``TranscriptionPipeline`` (ADR 0020, 0021).
extension TranscriptionPipeline {
    /// Snippet, or writing mode → mode style → vocabulary and replacements;
    /// then the cursor context and the mode's trailing space (ADR 0020, 0021).
    func written(_ transcript: String, session: DictationSession, run: inout Run) -> String {
        let mode = session.dictationMode
        if mode.usesSnippets, let snippet = SnippetMatcher.match(transcript, in: session.personalization.snippets) {
            // Delivered as written: only spacing may change around it.
            run.usedSnippet = true
            let text = session.formattingContext.map { format(snippet.expansion, .exact, $0) } ?? snippet.expansion
            return Self.trailingSpace(text, mode: mode, context: session.formattingContext)
        }
        // The injected writer serves the default rule set; a mode with rules
        // switched off runs its own configuration.
        var text =
            mode.cleanupRules == CleanupRule.allCases
            ? write(transcript, session.mode)
            : TextCleaner(configuration: mode.cleanupConfiguration).apply(transcript, mode: session.mode).text
        if mode.finalPunctuation == .omit {
            text = Self.omittingFinalPeriod(text)
        }
        if mode.usesPersonalization {
            let personalized = Personalizer(library: session.personalization).apply(text)
            text = personalized.text
            run.personalizations = personalized.transformations.count
        }
        guard text.contains(where: { !$0.isWhitespace }) else { return text }
        if let context = session.formattingContext {
            text = format(text, session.mode, context)
        }
        return Self.trailingSpace(text, mode: mode, context: session.formattingContext)
    }

    /// Drops one final period ("Message" style); `?`, `!`, and an ellipsis stay.
    public static func omittingFinalPeriod(_ text: String) -> String {
        guard text.hasSuffix("."), !text.hasSuffix("..") else { return text }
        return String(text.dropLast())
    }

    /// One space after the text, unless one is already there or follows the cursor.
    static func trailingSpace(_ text: String, mode: DictationMode, context: CursorContext?) -> String {
        guard mode.appendsSpace, let last = text.last, !last.isWhitespace,
            context?.followingText.first?.isWhitespace != true
        else { return text }
        return text + " "
    }

    /// Vocabulary hints for dictation; an instruction for voice editing gets none.
    func hints(for session: DictationSession) -> [String] {
        session.purpose == .dictation ? session.personalization.recognitionHints : []
    }
}
