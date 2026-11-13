package com.lemmetype.core.writing

/** How dictated text is written (ADR 0014). Raw values match Swift `WritingMode`. */
public enum class WritingMode(public val rawValue: String) {
    /** Only whitespace is normalised. Never rewrites a word. */
    EXACT("exact"),

    /** Deterministic cleanup rules over word tokens. */
    CLEAN("clean"),
}
