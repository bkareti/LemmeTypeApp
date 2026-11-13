package com.lemmetype.core.writing

/**
 * The decoding loop speech models fall into: the same phrase written again and again
 * (ADR 0028). A port of Swift `RepetitionLoop`. Words are compared without case and
 * without the punctuation and symbols around them.
 */
public object RepetitionLoop {
    /** Copies in a row from which a phrase counts as a loop ("no, no, no" is three and stays). */
    public const val MINIMUM_COPIES: Int = 4

    /** The longest phrase, in words, that is checked. */
    public const val LONGEST_PHRASE: Int = 8

    public data class Run(val phraseLength: Int, val copies: Int)

    public data class Collapsed(val text: String, val removedCopies: Int) {
        override fun toString(): String = "Collapsed(removedCopies=$removedCopies)"
    }

    /** `text` with every loop cut back to its first copy. Text without a loop comes back unchanged. */
    public fun collapse(text: String): Collapsed {
        val words = words(text)
        val keys = words.map(::key)
        val kept = mutableListOf<String>()
        var removed = 0
        var index = 0
        while (index < words.size) {
            val run = loop(keys, index)
            if (run != null) {
                kept += words.subList(index, index + run.phraseLength)
                removed += run.copies - 1
                index += run.phraseLength * run.copies
            } else {
                kept += words[index]
                index++
            }
        }
        return if (removed == 0) Collapsed(text, 0) else Collapsed(kept.joinToString(" "), removed)
    }

    /** The run with the most copies anywhere in `text`, for diagnostics and tests. */
    public fun longestRun(text: String): Run {
        val keys = words(text).map(::key)
        var longest = Run(phraseLength = 1, copies = if (keys.isEmpty()) 0 else 1)
        for (index in keys.indices) {
            for (length in 1..LONGEST_PHRASE) {
                val copies = copies(length, keys, index)
                if (copies > longest.copies) longest = Run(length, copies)
            }
        }
        return longest
    }

    private fun loop(keys: List<String>, index: Int): Run? {
        for (length in 1..LONGEST_PHRASE) {
            val copies = copies(length, keys, index)
            if (copies >= MINIMUM_COPIES) return Run(length, copies)
        }
        return null
    }

    private fun copies(length: Int, keys: List<String>, index: Int): Int {
        if (index + length > keys.size) return 0
        val phrase = keys.subList(index, index + length)
        if ("" in phrase) return 0
        var copies = 1
        var next = index + length
        while (next + length <= keys.size && keys.subList(next, next + length) == phrase) {
            copies++
            next += length
        }
        return copies
    }

    /** Splits on Unicode whitespace, like Swift's `split(whereSeparator: \.isWhitespace)`. */
    private fun words(text: String): List<String> {
        val words = mutableListOf<String>()
        val current = StringBuilder()
        for (char in text) {
            if (char.isWhitespace()) {
                if (current.isNotEmpty()) words += current.toString()
                current.setLength(0)
            } else {
                current.append(char)
            }
        }
        if (current.isNotEmpty()) words += current.toString()
        return words
    }

    /** Lower case without surrounding punctuation or symbols; empty for punctuation alone. */
    private fun key(word: String): String {
        val lower = word.lower()
        var start = 0
        var end = lower.length
        while (start < end && isPunctuationOrSymbol(lower.codePointAt(start))) {
            start += Character.charCount(lower.codePointAt(start))
        }
        while (end > start && isPunctuationOrSymbol(lower.codePointBefore(end))) {
            end -= Character.charCount(lower.codePointBefore(end))
        }
        return lower.substring(start, end)
    }

    private fun isPunctuationOrSymbol(codePoint: Int): Boolean =
        when (Character.getType(codePoint).toByte()) {
            Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
            Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
            Character.OTHER_PUNCTUATION, Character.MATH_SYMBOL, Character.CURRENCY_SYMBOL,
            Character.MODIFIER_SYMBOL, Character.OTHER_SYMBOL,
            -> true
            else -> false
        }
}
