package com.lemmetype.core.writing

/** Why a token is off limits to cleanup rules. */
internal enum class CleanupProtection {
    /** Inside quotes, or a line break the rules must keep. */
    VERBATIM,

    /** Contains a digit: amounts, phone numbers, versions. */
    NUMBER,

    /** URLs, email addresses, dotted names, and paths. */
    ADDRESS,

    /** Code identifiers (camelCase, snake_case) and backtick code. */
    IDENTIFIER,
}

/** A word with its surrounding punctuation split off, so rules can reason about the word alone. */
internal data class CleanupToken(
    var leading: String,
    var word: String,
    var trailing: String,
    var protection: CleanupProtection? = null,
) {
    val isProtected: Boolean get() = protection != null

    /** A line break token ("\n" or "\n\n"). */
    val isBreak: Boolean get() = word.isNotEmpty() && word.all { it == '\n' }

    val text: String get() = leading + word + trailing

    val lowercasedWord: String get() = word.lower()
}

/** Tokens being cleaned plus a log of every change. */
internal class CleanupDocument(text: String) {
    val tokens: MutableList<CleanupToken> = tokenize(text)
    val transformations: MutableList<CleanupTransformation> = mutableListOf()
    var currentRule: CleanupRule = CleanupRule.CAPITALIZATION

    val text: String
        get() {
            val output = StringBuilder()
            for (token in tokens) {
                if (token.isBreak) {
                    while (output.endsWith(" ")) output.setLength(output.length - 1)
                    output.append(token.word)
                } else {
                    if (output.isNotEmpty() && !output.endsWith("\n")) output.append(' ')
                    output.append(token.text)
                }
            }
            return output.toString()
        }

    fun record(before: String, after: String) {
        transformations.add(CleanupTransformation(currentRule, before, after))
    }

    companion object {
        val OPENING_PUNCTUATION: Set<Char> = setOf('"', '“', '‘', '(', '[', '\'')
        val CLOSING_PUNCTUATION: Set<Char> = setOf('.', ',', '!', '?', ';', ':', '"', '”', '’', ')', ']', '…', '\'')

        fun tokenize(text: String): MutableList<CleanupToken> {
            // Dashes used as separators ("Tuesday—sorry—Wednesday") become their own tokens.
            val spaced = text.replace("—", " — ").replace("–", " – ")
            val tokens = mutableListOf<CleanupToken>()
            var inQuote = false
            for ((offset, line) in spaced.split("\n").withIndex()) {
                if (offset > 0) {
                    val last = tokens.lastOrNull()
                    if (last != null && last.isBreak) {
                        last.word = "\n\n"
                    } else {
                        tokens.add(CleanupToken("", "\n", "", CleanupProtection.VERBATIM))
                    }
                }
                for (raw in line.split(' ')) {
                    if (raw.isEmpty()) continue
                    val token = split(raw)
                    val opens = token.leading.any { it == '"' || it == '“' }
                    val closes = token.trailing.any { it == '"' || it == '”' }
                    if (opens) inQuote = true
                    token.protection = if (inQuote) CleanupProtection.VERBATIM else protection(token.word)
                    if (closes) inQuote = false
                    tokens.add(token)
                }
            }
            return tokens
        }

        fun split(raw: String): CleanupToken {
            var start = 0
            var end = raw.length
            while (end - start > 1 && raw[start] in OPENING_PUNCTUATION) start++
            while (end - start > 1 && raw[end - 1] in CLOSING_PUNCTUATION) end--
            return CleanupToken(raw.substring(0, start), raw.substring(start, end), raw.substring(end))
        }

        /** Numbers, URLs, emails, and code-like identifiers are never rewritten. */
        fun protection(word: String): CleanupProtection? {
            val lower = word.lower()
            if (word.containsNumber()) return CleanupProtection.NUMBER
            if ('@' in word || "://" in lower || lower.startsWith("www.")) return CleanupProtection.ADDRESS
            if ('/' in word || '\\' in word) return CleanupProtection.ADDRESS
            // Dotted names: example.com, file.swift.
            if ('.' in word && word.firstIsLetter() && word.lastIsLetter()) return CleanupProtection.ADDRESS
            if ('_' in word || '`' in word) return CleanupProtection.IDENTIFIER
            // camelCase or PascalCase-inside words.
            val codePoints = word.codePointList()
            val interiorUppercase = codePoints.drop(1).any(Character::isUpperCase)
            return if (interiorUppercase && codePoints.any(Character::isLowerCase)) CleanupProtection.IDENTIFIER else null
        }
    }
}
