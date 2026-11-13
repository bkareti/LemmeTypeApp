package com.lemmetype.core.writing

/** The Clean Writing rules. Each one edits `CleanupDocument.tokens` and records every change. */
internal object CleanupRules {
    // MARK: Spoken punctuation

    /** Multi-word commands first so "question mark" wins over "mark". */
    private val SPOKEN_MARKS: List<Pair<List<String>, String>> =
        listOf(
            listOf("new", "paragraph") to "\n\n",
            listOf("new", "line") to "\n",
            listOf("question", "mark") to "?",
            listOf("exclamation", "mark") to "!",
            listOf("exclamation", "point") to "!",
            listOf("full", "stop") to ".",
            listOf("comma") to ",",
            listOf("semicolon") to ";",
        )

    fun spokenPunctuation(document: CleanupDocument) {
        val tokens = document.tokens
        var index = 0
        while (index < tokens.size) {
            val match = if (index > 0) spokenMark(index, tokens) else null
            if (match == null) {
                index++
                continue
            }
            val (words, mark) = match
            val previous = index - 1
            val spoken = tokens.subList(index, index + words.size).joinToString(" ") { it.text }
            tokens.subList(index, index + words.size).clear()
            if (mark.startsWith("\n")) {
                tokens.add(index, CleanupToken("", mark, "", CleanupProtection.VERBATIM))
                index++
            } else if (!tokens[previous].isBreak) {
                tokens[previous].trailing = mergedTrailing(tokens[previous].trailing, mark)
            }
            document.record(spoken, mark)
        }
        // "period" is a mark only at the very end, where it cannot be the noun.
        val last = tokens.lastOrNull()
        if (tokens.size > 1 && last != null && last.lowercasedWord == "period" && !last.isProtected &&
            (last.trailing.isEmpty() || last.trailing == ".")
        ) {
            tokens.removeAt(tokens.lastIndex)
            val end = tokens.lastIndex
            tokens[end].trailing = mergedTrailing(tokens[end].trailing, ".")
            document.record(last.text, ".")
        }
    }

    private fun spokenMark(index: Int, tokens: List<CleanupToken>): Pair<List<String>, String>? =
        SPOKEN_MARKS.firstOrNull { (words, _) ->
            index + words.size <= tokens.size &&
                words.withIndex().all { (offset, word) ->
                    val token = tokens[index + offset]
                    !token.isProtected && token.lowercasedWord == word && token.leading.isEmpty()
                }
        }

    /** Replaces a trailing comma the recogniser added with the spoken mark. */
    private fun mergedTrailing(trailing: String, mark: String): String = trailing.filter { it !in ",.;!?" } + mark

    // MARK: Self-correction

    private val CORRECTION_MARKERS: List<List<String>> = listOf(listOf("sorry"), listOf("i", "mean"), listOf("no", "wait"))
    private val WEEKDAYS = setOf("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
    private val MONTHS =
        setOf(
            "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
            "november", "december",
        )
    private val NUMBER_WORDS =
        setOf(
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
            "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
            "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred",
        )

    private enum class WordKind { WEEKDAY, MONTH, NUMBER }

    private fun kind(token: CleanupToken): WordKind? {
        val word = token.lowercasedWord
        if (word in WEEKDAYS) return WordKind.WEEKDAY
        if (word.allNumbers() || word in NUMBER_WORDS) return WordKind.NUMBER
        if (word in MONTHS && word != "may" && word != "march") return WordKind.MONTH
        return null
    }

    /**
     * `X <marker> Y` → `Y` only when X and Y are single words of the same kind and the marker
     * is set off by dashes or commas or stands alone between them.
     */
    fun selfCorrection(document: CleanupDocument) {
        val tokens = document.tokens
        var index = 1
        while (index < tokens.size) {
            val replaced = correction(index, tokens)
            if (replaced == null) {
                index++
                continue
            }
            val (start, end) = replaced
            val before = tokens.subList(start, end + 1).joinToString(" ") { it.text }
            val corrected = tokens[end].copy(leading = tokens[start].leading)
            tokens.subList(start, end + 1).clear()
            tokens.add(start, corrected)
            document.record(before, corrected.text)
            index = start + 1
        }
    }

    private fun correction(index: Int, tokens: List<CleanupToken>): Pair<Int, Int>? {
        for (marker in CORRECTION_MARKERS) {
            var cursor = index
            if (isDash(tokens[cursor])) cursor++
            if (cursor + marker.size >= tokens.size) continue
            if (!marker.withIndex().all { (offset, word) -> tokens[cursor + offset].lowercasedWord == word }) continue
            var next = cursor + marker.size
            if (next < tokens.size && isDash(tokens[next])) next++
            val start = index - 1
            if (next >= tokens.size) continue
            val startKind = kind(tokens[start]) ?: continue
            if (startKind != kind(tokens[next])) continue
            if (!tokens[start].trailing.all { it == ',' }) continue
            if (!tokens[cursor + marker.size - 1].trailing.all { it == ',' }) continue
            return start to next
        }
        return null
    }

    private fun isDash(token: CleanupToken): Boolean = token.word == "—" || token.word == "–" || token.word == "-"

    // MARK: Fillers and repeats

    private val FILLERS = setOf("um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "mm")

    fun fillerWords(document: CleanupDocument) {
        val tokens = document.tokens
        var index = 0
        while (index < tokens.size) {
            val token = tokens[index]
            if (token.isProtected || token.lowercasedWord !in FILLERS) {
                index++
                continue
            }
            tokens.removeAt(index)
            val terminal = token.trailing.filter { it in ".?!" }
            if (terminal.isNotEmpty() && index > 0) {
                tokens[index - 1].trailing = mergedTrailing(tokens[index - 1].trailing, terminal)
            }
            if (index < tokens.size && token.leading.isNotEmpty()) {
                tokens[index].leading = token.leading + tokens[index].leading
            }
            document.record(token.text, "")
        }
    }

    /** Doubles that are grammatical ("had had", "that that") are kept. */
    private val LEGITIMATE_DOUBLES = setOf("had", "that", "is", "do", "no", "very", "so", "bye", "ha", "knock")

    fun repeatedWords(document: CleanupDocument) {
        val tokens = document.tokens
        var index = 1
        while (index < tokens.size) {
            val previous = tokens[index - 1]
            val current = tokens[index]
            val isRepeat =
                !previous.isProtected && !current.isProtected && !previous.isBreak &&
                    previous.trailing.isEmpty() && current.leading.isEmpty() && previous.word.isNotEmpty() &&
                    previous.lowercasedWord == current.lowercasedWord &&
                    current.lowercasedWord !in LEGITIMATE_DOUBLES
            if (isRepeat) {
                val before = previous.text + " " + current.text
                tokens.removeAt(index)
                tokens[index - 1] = previous.copy(trailing = current.trailing)
                document.record(before, tokens[index - 1].text)
            } else {
                index++
            }
        }
    }

    // MARK: Capitalization and terminal punctuation

    private val PRONOUN_I = setOf("i", "i'm", "i've", "i'll", "i'd", "i’m", "i’ve", "i’ll", "i’d")

    fun capitalization(document: CleanupDocument) {
        val tokens = document.tokens
        var startsSentence = true
        for (index in tokens.indices) {
            val token = tokens[index]
            if (token.isBreak) {
                startsSentence = true
                continue
            }
            if (!token.isProtected && token.word.firstIsLowercase() &&
                (startsSentence || token.lowercasedWord in PRONOUN_I)
            ) {
                val updated = token.copy(word = token.word.capitalizedFirst())
                if (updated != token) {
                    tokens[index] = updated
                    document.record(token.text, updated.text)
                }
            }
            if (token.word.isNotEmpty() && !isDash(token)) {
                startsSentence = token.trailing.any { it in ".?!" }
            }
        }
    }

    private val TERMINATORS = setOf('.', '?', '!', '…', ':', ';')

    fun terminalPunctuation(document: CleanupDocument) {
        val tokens = document.tokens
        val index = tokens.indexOfLast { !it.isBreak }
        if (index < 0) return
        val token = tokens[index]
        // A period may follow an identifier, but not a number, address, or quote,
        // where it could read as part of the protected text.
        if (token.protection != null && token.protection != CleanupProtection.IDENTIFIER) return
        if (token.trailing.any { it in TERMINATORS }) return
        if (token.word.isEmpty() || token.word.last() in TERMINATORS) return
        val updated = token.copy(trailing = token.trailing.filter { it != ',' } + ".")
        tokens[index] = updated
        document.record(token.text, updated.text)
    }
}
