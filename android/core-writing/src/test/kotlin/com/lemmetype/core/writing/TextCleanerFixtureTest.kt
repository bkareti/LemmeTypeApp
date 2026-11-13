package com.lemmetype.core.writing

import com.lemmetype.core.testing.SharedFixtures
import kotlinx.serialization.Serializable
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** `shared/fixtures/cleanup-corpus.json`: the same cases the Swift `TextCleaner` passes. */
class TextCleanerFixtureTest {
    @Serializable
    data class Case(val category: String, val input: String, val clean: String, val rules: List<String>)

    @Serializable
    data class Whitespace(val input: String, val exact: String)

    @Serializable
    data class Change(val rule: String, val before: String, val after: String)

    @Serializable
    data class Transformation(val input: String, val expected: List<Change>)

    @Serializable
    data class Corpus(
        val version: Int,
        val cases: List<Case>,
        val whitespace: List<Whitespace>,
        val transformations: List<Transformation>,
        val protected: List<String>,
    )

    private val corpus: Corpus = SharedFixtures.decode("cleanup-corpus.json")
    private val cleaner = TextCleaner()

    @Test
    fun `corpus covers every rule`() {
        assertTrue(corpus.cases.size >= 39)
        assertEquals(CleanupRule.entries.map { it.rawValue }.toSet(), corpus.cases.flatMap { it.rules }.toSet())
    }

    @TestFactory
    fun `clean writing matches the shared corpus`(): List<DynamicTest> =
        corpus.cases.map { case ->
            DynamicTest.dynamicTest("${case.category}: ${case.input}") {
                val result = cleaner.apply(case.input, WritingMode.CLEAN)
                assertEquals(case.clean, result.text)
                assertEquals(case.rules.toSet(), result.transformations.map { it.rule.rawValue }.toSet())
            }
        }

    @TestFactory
    fun `exact dictation keeps every word`(): List<DynamicTest> =
        corpus.cases.map { case ->
            DynamicTest.dynamicTest(case.input) {
                val result = cleaner.apply("  " + case.input + "   ", WritingMode.EXACT)
                assertEquals(case.input, result.text)
                assertTrue(result.transformations.isEmpty())
            }
        }

    @Test
    fun `clean writing is deterministic`() {
        for (case in corpus.cases) {
            assertEquals(cleaner.apply(case.input, WritingMode.CLEAN), cleaner.apply(case.input, WritingMode.CLEAN))
        }
    }

    @Test
    fun `whitespace and recorded changes match`() {
        for (item in corpus.whitespace) assertEquals(item.exact, TextCleaner.normalizeWhitespace(item.input))
        for (item in corpus.transformations) {
            val changes =
                cleaner.apply(item.input, WritingMode.CLEAN).transformations.map {
                    Change(it.rule.rawValue, it.before, it.after)
                }
            assertEquals(item.expected, changes)
        }
    }

    @Test
    fun `protected tokens survive clean writing`() {
        val input = "um " + corpus.protected.joinToString(" um ")
        val output = cleaner.apply(input, WritingMode.CLEAN).text
        for (token in corpus.protected) assertTrue(token in output, "$token changed")
    }
}
