package com.lemmetype.core.domain

import com.lemmetype.core.testing.SharedFixtures
import kotlinx.serialization.Serializable
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/** The JSON files in `shared/fixtures/`: the same tables the Swift `SharedFixturesTests` check. */
class SharedFixtureTests {
    @Serializable
    data class Row(val from: String, val event: String, val to: String?)

    @Serializable
    data class Transitions(val states: List<String>, val events: List<String>, val transitions: List<Row>)

    private val error = AudioCaptureError.Interrupted
    private val issue = DictationIssue.ReviewText
    private val states =
        listOf(
            RecorderState.Idle, RecorderState.Preparing, RecorderState.Recording, RecorderState.Stopping,
            RecorderState.Processing, RecorderState.Completed, RecorderState.Cancelled, RecorderState.Failed(error),
            RecorderState.NeedsAttention(issue),
        )
    private val events =
        listOf(
            RecorderEvent.Activate, RecorderEvent.CaptureStarted, RecorderEvent.StopRequested, RecorderEvent.CaptureFinished,
            RecorderEvent.ProcessingFinished, RecorderEvent.Cancel, RecorderEvent.Fail(error),
            RecorderEvent.ProcessingNeedsAttention(issue), RecorderEvent.Retry, RecorderEvent.Reset,
        )

    @Test
    fun `recorder transitions match the shared table`() {
        val table: Transitions = SharedFixtures.decode("recorder-transitions.json")
        assertEquals(table.states, states.map { it.name })
        assertEquals(table.events, events.map { it.name })
        assertEquals(states.size * events.size, table.transitions.size)
        for (row in table.transitions) {
            val state = assertNotNull(states.firstOrNull { it.name == row.from })
            val event = assertNotNull(events.firstOrNull { it.name == row.event })
            assertEquals(row.to, RecorderStateMachine.transition(state, event)?.name, "${row.from} + ${row.event}")
        }
    }

    @Test
    fun `payloads are carried through`() {
        assertEquals(RecorderState.Failed(error), RecorderStateMachine.transition(RecorderState.Recording, RecorderEvent.Fail(error)))
        assertEquals(
            RecorderState.NeedsAttention(issue),
            RecorderStateMachine.transition(RecorderState.Processing, RecorderEvent.ProcessingNeedsAttention(issue)),
        )
    }

    @Serializable
    data class ErrorEntry(val case: String, val identifier: String, val retryable: Boolean)

    @Serializable
    data class Errors(val errors: List<ErrorEntry>)

    private val allErrors =
        listOf(
            RecognitionError.Cancelled, RecognitionError.AssetsMissing, RecognitionError.Unsupported(UnsupportedReason.LANGUAGE),
            RecognitionError.PermissionDenied, RecognitionError.AudioUnreadable, RecognitionError.NoSpeechDetected,
            RecognitionError.SilentAudio, RecognitionError.ModelLoadFailed, RecognitionError.LanguageUncertain,
            RecognitionError.EngineFailure(1), RecognitionError.CloudOffline, RecognitionError.CloudKeyRejected,
            RecognitionError.SubscriptionRequired, RecognitionError.CloudRateLimited, RecognitionError.CloudQuotaExhausted,
            RecognitionError.CloudServiceFailed, RecognitionError.CloudUnavailable,
        )

    /** Exhaustive on purpose: a new Kotlin case does not compile until it is named here and in the fixture. */
    private fun caseOf(error: RecognitionError): String =
        when (error) {
            RecognitionError.Cancelled -> "cancelled"
            RecognitionError.AssetsMissing -> "assets-missing"
            is RecognitionError.Unsupported -> "unsupported"
            RecognitionError.PermissionDenied -> "permission-denied"
            RecognitionError.AudioUnreadable -> "audio-unreadable"
            RecognitionError.NoSpeechDetected -> "no-speech-detected"
            RecognitionError.SilentAudio -> "silent-audio"
            RecognitionError.ModelLoadFailed -> "model-load-failed"
            RecognitionError.LanguageUncertain -> "language-uncertain"
            is RecognitionError.EngineFailure -> "engine-failure"
            RecognitionError.CloudOffline -> "cloud-offline"
            RecognitionError.CloudKeyRejected -> "cloud-key-rejected"
            RecognitionError.SubscriptionRequired -> "subscription-required"
            RecognitionError.CloudRateLimited -> "cloud-rate-limited"
            RecognitionError.CloudQuotaExhausted -> "cloud-quota-exhausted"
            RecognitionError.CloudServiceFailed -> "cloud-service-failed"
            RecognitionError.CloudUnavailable -> "cloud-unavailable"
        }

    @Test
    fun `recognition errors match the shared list`() {
        val shared: Errors = SharedFixtures.decode("recognition-errors.json")
        assertEquals(shared.errors, allErrors.map { ErrorEntry(it.caseName, it.identifier, it.isRetryable) })
        assertEquals(shared.errors.map { it.case }, allErrors.map(::caseOf))
    }

    @Serializable
    data class File(val name: String, val url: String, val sha256: String, val bytes: Long)

    @Serializable
    data class Model(
        val id: String,
        val displayName: String,
        val version: String,
        val engine: String,
        val files: List<File>,
        val languages: List<String>,
        val tasks: List<String>,
        val tier: String,
        val runtimeMemoryBytes: Long,
        val license: String,
    )

    @Serializable
    data class Catalog(val allowedHosts: List<String>, val models: List<Model>)

    @Test
    fun `model catalog matches the shared pins`() {
        val shared: Catalog = SharedFixtures.decode("model-catalog.json")
        val kotlin =
            ModelCatalog.ALL.map { asset ->
                Model(
                    asset.id.rawValue, asset.displayName, asset.version, asset.engine.rawValue,
                    asset.files.map { File(it.name, it.url, it.sha256, it.bytes) },
                    asset.languages, asset.tasks.map { it.rawValue }.sorted(), asset.tier.rawValue,
                    asset.runtimeMemoryBytes, asset.license,
                )
            }
        assertEquals(shared.models, kotlin)
        assertEquals(shared.allowedHosts.toSet(), ModelCatalog.ALLOWED_HOSTS)
    }
}
