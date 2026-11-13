package com.lemmetype.core.writing

/** One deterministic cleanup rule. Raw values are stable identifiers shared with Swift. */
public enum class CleanupRule(public val rawValue: String) {
    /** "comma", "question mark", "new line", … become punctuation. */
    SPOKEN_PUNCTUATION("spoken-punctuation"),

    /** "Tuesday—sorry—Wednesday" becomes "Wednesday" when both words are the same kind. */
    SELF_CORRECTION("self-correction"),

    /** Standalone hesitation sounds: um, uh, er, erm, ah, hmm. */
    FILLER_WORDS("filler-words"),

    /** An immediately repeated word ("the the"), except legitimate doubles. */
    REPEATED_WORDS("repeated-words"),

    /** Sentence starts and the pronoun "I". */
    CAPITALIZATION("capitalization"),

    /** A final period when the text has no terminal punctuation. */
    TERMINAL_PUNCTUATION("terminal-punctuation"),
    ;

    public companion object {
        public fun fromRawValue(raw: String): CleanupRule? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** Which Clean Writing rules run. */
public data class CleanupConfiguration(
    val enabledRules: Set<CleanupRule> = CleanupRule.entries.toSet(),
) {
    public fun isEnabled(rule: CleanupRule): Boolean = rule in enabledRules

    public companion object {
        public val DEFAULT: CleanupConfiguration = CleanupConfiguration()
    }
}

/** A single change made by a rule. In memory only: it contains dictated text. */
public data class CleanupTransformation(
    val rule: CleanupRule,
    val before: String,
    val after: String,
) {
    // Dictated text must never reach a log through toString().
    override fun toString(): String = "CleanupTransformation(rule=${rule.rawValue})"
}

public data class CleanupResult(
    val text: String,
    val transformations: List<CleanupTransformation>,
) {
    override fun toString(): String = "CleanupResult(changes=${transformations.size})"
}

/**
 * Exact Dictation and deterministic Clean Writing, a port of Swift `TextCleaner`
 * (ADR 0014, ADR 0035). `shared/fixtures/cleanup-corpus.json` holds the cases both
 * implementations must pass.
 *
 * - Exact only normalises whitespace (trims, collapses runs, keeps line breaks).
 * - Clean runs the enabled rules in a fixed order over word tokens. Numbers, URLs,
 *   email addresses, identifiers, and text inside quotes are protected.
 */
public class TextCleaner(
    public val configuration: CleanupConfiguration = CleanupConfiguration.DEFAULT,
) {
    public fun apply(text: String, mode: WritingMode): CleanupResult =
        when (mode) {
            WritingMode.EXACT -> CleanupResult(normalizeWhitespace(text), emptyList())
            WritingMode.CLEAN -> {
                val document = CleanupDocument(normalizeWhitespace(text))
                for ((rule, run) in RULES) {
                    if (!configuration.isEnabled(rule)) continue
                    document.currentRule = rule
                    run(document)
                }
                CleanupResult(document.text, document.transformations.toList())
            }
        }

    public companion object {
        private val RULES: List<Pair<CleanupRule, (CleanupDocument) -> Unit>> =
            listOf(
                CleanupRule.SPOKEN_PUNCTUATION to CleanupRules::spokenPunctuation,
                CleanupRule.SELF_CORRECTION to CleanupRules::selfCorrection,
                CleanupRule.FILLER_WORDS to CleanupRules::fillerWords,
                CleanupRule.REPEATED_WORDS to CleanupRules::repeatedWords,
                CleanupRule.CAPITALIZATION to CleanupRules::capitalization,
                CleanupRule.TERMINAL_PUNCTUATION to CleanupRules::terminalPunctuation,
            )

        /** Trims, collapses spaces and tabs, and keeps at most one blank line. */
        public fun normalizeWhitespace(text: String): String {
            val lines =
                text.split("\n").map { line ->
                    line.split(' ', '\t', '\r').filter { it.isNotEmpty() }.joinToString(" ")
                }
            val result = mutableListOf<String>()
            for (line in lines) {
                if (line.isEmpty() && (result.lastOrNull()?.isEmpty() ?: true)) continue
                result.add(line)
            }
            while (result.lastOrNull()?.isEmpty() == true) result.removeAt(result.lastIndex)
            return result.joinToString("\n")
        }
    }
}
