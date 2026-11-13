package com.lemmetype.core.domain

import com.lemmetype.core.testing.FakeSpeechEngine
import com.lemmetype.core.testing.SpeechEngineContract
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds

@OptIn(ExperimentalCoroutinesApi::class)
class RecognitionRunnerTest {
    @TempDir
    lateinit var folder: File

    private fun request(language: String = "en-US"): RecognitionRequest {
        val audio = File(folder, "LemmeTypeTests-recording.pcm").apply { writeBytes(ByteArray(32)) }
        return RecognitionRequest(RecordedAudio(audio.path, durationSeconds = 2.0), language)
    }

    private val runner = RecognitionRunner()

    @Test
    fun `a ready engine returns its transcript and updates`() =
        runTest {
            val engine = FakeSpeechEngine(text = "Ship it.")
            val updates = mutableListOf<RecognitionUpdate>()
            val transcript = runner.run(engine, request()) { updates += it }
            assertEquals("Ship it.", transcript.text)
            assertEquals(listOf<RecognitionUpdate>(RecognitionUpdate.Progress(0.5)), updates)
        }

    @Test
    fun `an engine that is not ready is never called`() =
        runTest {
            val engine = FakeSpeechEngine(availability = EngineAvailability.AssetsMissing)
            val failure = assertFailsWith<RecognitionFailure> { runner.run(engine, request()) }
            assertEquals(RecognitionError.AssetsMissing, failure.error)
            assertEquals(0, engine.recognizeCalls)
        }

    @Test
    fun `an unsupported language fails without calling the engine`() =
        runTest {
            val engine = FakeSpeechEngine()
            val failure = assertFailsWith<RecognitionFailure> { runner.run(engine, request(language = "te-IN")) }
            assertEquals(RecognitionError.Unsupported(UnsupportedReason.LANGUAGE), failure.error)
            assertEquals(0, engine.recognizeCalls)
        }

    @Test
    fun `automatic needs language detection`() =
        runTest {
            val failure = assertFailsWith<RecognitionFailure> { runner.run(FakeSpeechEngine(), request(SpokenLanguages.AUTOMATIC)) }
            assertEquals(RecognitionError.Unsupported(UnsupportedReason.LANGUAGE), failure.error)
        }

    @Test
    fun `a cancelled session never succeeds and gets no late updates`() =
        runTest {
            val engine = FakeSpeechEngine(work = 5.seconds, lateUpdates = listOf(RecognitionUpdate.Partial("late")))
            val updates = mutableListOf<RecognitionUpdate>()
            val session = async { runner.run(engine, request()) { updates += it } }
            runCurrent()
            advanceTimeBy(1.seconds)
            session.cancel()
            assertFailsWith<CancellationException> { session.await() }
            assertTrue(updates.none { it is RecognitionUpdate.Partial })
        }

    @Test
    fun `an engine failure passes through and a crash becomes engine failure`() =
        runTest {
            val failing = FakeSpeechEngine(failure = RecognitionError.NoSpeechDetected)
            assertEquals(RecognitionError.NoSpeechDetected, assertFailsWith<RecognitionFailure> { runner.run(failing, request()) }.error)
            val crashing = FakeSpeechEngine(crash = true)
            assertEquals(RecognitionError.EngineFailure(-1), assertFailsWith<RecognitionFailure> { runner.run(crashing, request()) }.error)
        }

    @Test
    fun `the fake engine passes the engine contract`() =
        runTest {
            assertEquals(emptyList(), SpeechEngineContract.verify(FakeSpeechEngine(), request()))
            assertEquals(
                emptyList(),
                SpeechEngineContract.verify(FakeSpeechEngine(availability = EngineAvailability.PermissionUnavailable), request()),
            )
        }

    @Test
    fun `the contract catches an engine that ignores availability`() =
        runTest {
            val careless =
                object : SpeechEngine by FakeSpeechEngine() {
                    override suspend fun availability(): EngineAvailability = EngineAvailability.AssetsMissing
                }
            assertTrue(SpeechEngineContract.verify(careless, request()).any { "returned a transcript" in it })
        }

    @Test
    fun `requests and transcripts never print dictated text`() {
        val transcript = Transcript(text = "secret plan", engine = RecognitionEngineId.WHISPER, language = "en", audioDurationSeconds = 1.0, processingDurationSeconds = 0.1)
        assertTrue("secret" !in transcript.toString())
        assertTrue("secret" !in request().copy(hints = listOf("secret")).toString())
        assertTrue("secret" !in RecognitionUpdate.Partial("secret").toString())
    }
}
