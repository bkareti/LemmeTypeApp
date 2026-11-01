/// The dictation text steps of ``TranscriptionPipeline`` (ADR 0020, 0021).
extension TranscriptionPipeline {
    /// Snippet, or writing mode → mode style → vocabulary and replacements;
    /// then the cursor context and the mode's trailing space (ADR 0020, 0021).
    ///
    /// `language` is the language of `transcript`. Clean Writing, the context
    /// formatter, and the final-period style are English rules, so text in
    /// any other language is written Exact (spacing only), and the English
    /// text of a translation gets the full treatment (E9-S4).
    func written(_ transcript: String, language: String, session: DictationSession, run: inout Run) -> String {
        let before = writtenBeforeStyle(transcript, language: language, session: session, run: &run)
        return before.isFinal ? before.text : finished(before.text, language: language, session: session)
    }

    /// Text that is ready for the optional tone and format step (E10-S3).
    struct WrittenText {
        var text: String
        /// Snippets and empty text skip the style step and the final formatting.
        var isFinal: Bool
    }

    /// Everything up to, and not including, the cursor context and trailing space.
    func writtenBeforeStyle(_ transcript: String, language: String, session: DictationSession, run: inout Run)
        -> WrittenText
    {
        let mode = session.dictationMode
        let isEnglish = SpokenLanguages.isEnglish(language)
        if mode.usesSnippets, let snippet = SnippetMatcher.match(transcript, in: session.personalization.snippets) {
            // Delivered as written: only spacing may change around it.
            run.usedSnippet = true
            let text = session.formattingContext.map { format(snippet.expansion, .exact, $0) } ?? snippet.expansion
            return WrittenText(
                text: Self.trailingSpace(text, mode: mode, context: session.formattingContext), isFinal: true)
        }
        // The injected writer serves the default rule set; a mode with rules
        // switched off runs its own configuration.
        var text =
            if !isEnglish {
                write(transcript, .exact)
            } else if mode.cleanupRules == CleanupRule.allCases {
                write(transcript, session.mode)
            } else {
                TextCleaner(configuration: mode.cleanupConfiguration).apply(transcript, mode: session.mode).text
            }
        if isEnglish, mode.finalPunctuation == .omit {
            text = Self.omittingFinalPeriod(text)
        }
        if mode.usesPersonalization {
            let personalized = Personalizer(library: session.personalization).apply(text)
            text = personalized.text
            run.personalizations = personalized.transformations.count
        }
        return WrittenText(text: text, isFinal: !text.contains(where: { !$0.isWhitespace }))
    }

    /// The cursor context and the mode's trailing space, after any rewrite.
    func finished(_ text: String, language: String, session: DictationSession) -> String {
        var text = text
        if SpokenLanguages.isEnglish(language), let context = session.formattingContext {
            text = format(text, session.mode, context)
        }
        return Self.trailingSpace(text, mode: session.dictationMode, context: session.formattingContext)
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
