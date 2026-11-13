package com.lemmetype.core.writing

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

/** The Swift `RepetitionLoopTests`, case for case. */
class RepetitionLoopTest {
    @Test
    fun `a phrase repeated four times is cut to one copy`() {
        val result = RepetitionLoop.collapse("Send it today. Thank you. Thank you. Thank you. Thank you.")
        assertEquals("Send it today. Thank you.", result.text)
        assertEquals(3, result.removedCopies)
    }

    @Test
    fun `three copies are what people say and stay`() {
        val text = "No, no, no, that is wrong."
        assertEquals(RepetitionLoop.Collapsed(text, 0), RepetitionLoop.collapse(text))
    }

    @Test
    fun `text without a loop comes back unchanged spacing included`() {
        val text = "Ship it  on Wednesday.\nThanks"
        assertEquals(RepetitionLoop.Collapsed(text, 0), RepetitionLoop.collapse(text))
    }

    @Test
    fun `case and punctuation do not hide a loop`() {
        val result = RepetitionLoop.collapse("okay Okay, OKAY. okay! fine")
        assertEquals("okay fine", result.text)
        assertEquals(3, result.removedCopies)
    }

    @Test
    fun `a loop in an Indic script is cut`() {
        val phrase = "मैं ठीक हूँ।"
        val result = RepetitionLoop.collapse(List(6) { phrase }.joinToString(" ") + " बस")
        assertEquals("मैं ठीक हूँ। बस", result.text)
        assertEquals(5, result.removedCopies)
    }

    @Test
    fun `the shortest repeating phrase is kept`() {
        assertEquals("la", RepetitionLoop.collapse("la la la la la la la la").text)
    }

    @Test
    fun `phrases longer than the limit are not checked`() {
        val phrase = (1..RepetitionLoop.LONGEST_PHRASE + 1).joinToString(" ") { "w$it" }
        assertEquals(0, RepetitionLoop.collapse(List(5) { phrase }.joinToString(" ")).removedCopies)
    }

    @Test
    fun `punctuation alone is never a phrase`() {
        val text = "Wait - - - - what"
        assertEquals(RepetitionLoop.Collapsed(text, 0), RepetitionLoop.collapse(text))
    }

    @Test
    fun `longest run reports copies and phrase length`() {
        assertEquals(RepetitionLoop.Run(3, 3), RepetitionLoop.longestRun("a b c a b c a b c d"))
        assertEquals(RepetitionLoop.Run(1, 1), RepetitionLoop.longestRun("one two"))
        assertEquals(RepetitionLoop.Run(1, 0), RepetitionLoop.longestRun(""))
    }
}
