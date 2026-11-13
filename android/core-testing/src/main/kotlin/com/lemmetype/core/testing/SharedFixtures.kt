package com.lemmetype.core.testing

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import java.io.File

/**
 * Reads the JSON files in the repository's `shared/fixtures/` folder (E14-S7). The Gradle
 * build passes the folder as the `lemmetype.fixtures` system property, so tests never
 * guess a path. The Swift tests read the same files (`SharedFixturesTests`).
 */
public object SharedFixtures {
    /** Unknown keys (notes, version) are allowed so a fixture can document itself. */
    public val json: Json = Json { ignoreUnknownKeys = true }

    public val folder: File
        get() {
            val path =
                System.getProperty("lemmetype.fixtures")
                    ?: error("lemmetype.fixtures is not set; run the tests through Gradle")
            return File(path).also { check(it.isDirectory) { "No fixtures folder at $path" } }
        }

    public fun text(name: String): String = File(folder, name).readText()

    public fun element(name: String): JsonElement = json.parseToJsonElement(text(name))

    public inline fun <reified T> decode(name: String): T = json.decodeFromString(text(name))
}
