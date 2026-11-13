package com.lemmetype.core.writing

import org.junit.jupiter.api.Test
import kotlin.random.Random
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TextCleanerTest {
    @Test
    fun `each rule can be turned off`() {
        val input = "um hello comma the the world"
        for (rule in CleanupRule.entries) {
            val result = TextCleaner(CleanupConfiguration(CleanupRule.entries.toSet() - rule)).apply(input, WritingMode.CLEAN)
            assertFalse(result.transformations.any { it.rule == rule }, rule.rawValue)
        }
        assertEquals(input, TextCleaner(CleanupConfiguration(emptySet())).apply(input, WritingMode.CLEAN).text)
    }

    @Test
    fun `exact changes only whitespace for any input`() {
        val alphabet = listOf("a", "B", "um", "1", ".", ",", "\"", "—", " ", "  ", "\t", "\n", "é", "😀", "I", "the")
        val random = Random(7)
        repeat(500) {
            val input = (0 until random.nextInt(0, 30)).joinToString("") { alphabet.random(random) }
            val output = TextCleaner().apply(input, WritingMode.EXACT).text
            assertEquals(input.filterNot { it.isWhitespace() }, output.filterNot { it.isWhitespace() })
        }
    }

    @Test
    fun `protected spans never change in clean writing`() {
        val spans = listOf("v2.1.0", "https://example.org/a_b", "x@y.io", "fetchData", "`ls -la`", "\"um um\"")
        val random = Random(11)
        repeat(200) {
            val words = (0 until 6).map { if (random.nextBoolean()) spans.random(random) else listOf("um", "the", "comma").random(random) }
            val output = TextCleaner().apply(words.joinToString(" "), WritingMode.CLEAN).text
            for (span in words.filter { it in spans }) assertTrue(span in output, "$span lost in $output")
        }
    }

    @Test
    fun `transformations never print dictated text`() {
        val result = TextCleaner().apply("um secret words", WritingMode.CLEAN)
        assertFalse("secret" in result.toString())
        assertFalse(result.transformations.any { "secret" in it.toString() })
    }
}
