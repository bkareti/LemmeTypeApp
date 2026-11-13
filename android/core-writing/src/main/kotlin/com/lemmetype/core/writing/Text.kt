package com.lemmetype.core.writing

// Character tests that match Swift's `Character` properties for the text LemmeType sees.
// Kotlin `Char` is a UTF-16 unit, so these work on code points.

internal fun String.codePointList(): List<Int> = codePoints().toArray().toList()

internal fun isNumber(codePoint: Int): Boolean =
    when (Character.getType(codePoint).toByte()) {
        Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
        else -> false
    }

internal fun String.containsNumber(): Boolean = codePoints().anyMatch(::isNumber)

internal fun String.allNumbers(): Boolean = codePoints().allMatch(::isNumber)

internal fun String.firstIsLetter(): Boolean = isNotEmpty() && Character.isLetter(codePointAt(0))

internal fun String.lastIsLetter(): Boolean = isNotEmpty() && Character.isLetter(codePointBefore(length))

/// Swift's `String.lowercased()` does not depend on the user's locale; neither does this.
internal fun String.lower(): String = lowercase()

/// The first character in upper case, the rest unchanged.
internal fun String.capitalizedFirst(): String {
    if (isEmpty()) return this
    val first = codePointAt(0)
    val width = Character.charCount(first)
    return String(Character.toChars(first)).uppercase() + substring(width)
}

internal fun String.firstIsLowercase(): Boolean = isNotEmpty() && Character.isLowerCase(codePointAt(0))
