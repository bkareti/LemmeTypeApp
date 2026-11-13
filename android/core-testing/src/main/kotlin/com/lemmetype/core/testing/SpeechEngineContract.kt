package com.lemmetype.core.testing

import com.lemmetype.core.domain.DiagnosticValue
import com.lemmetype.core.domain.EngineAvailability
import com.lemmetype.core.domain.ProcessingLocation
import com.lemmetype.core.domain.RecognitionError
import com.lemmetype.core.domain.RecognitionFailure
import com.lemmetype.core.domain.RecognitionRequest
import com.lemmetype.core.domain.SpeechEngine
import com.lemmetype.core.domain.Transcript
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.job
import kotlinx.coroutines.withTimeout
import java.io.File
import kotlin.math.abs
import kotlin.time.Duration.Companion.seconds

/**
 * Behaviour every [SpeechEngine] must show (Swift `RecognitionEngineContract`). Returns
 * readable violations instead of asserting; a test checks the list is empty.
 */
public object SpeechEngineContract {
    /** Generous on purpose: an engine that ignores cancellation runs its whole job or never returns. */
    public val CANCELLATION_DEADLINE: kotlin.time.Duration = 10.seconds

    public suspend fun verify(
        engine: SpeechEngine,
        request: RecognitionRequest,
        location: ProcessingLocation = ProcessingLocation.ON_DEVICE,
    ): List<String> {
        val issues = checkDescriptor(engine, location).toMutableList()
        val availability = engine.availability()
        issues += if (availability.isReady) checkRecognition(engine, request) else checkRefuses(engine, availability, request)
        issues += checkCancelledBeforeStart(engine, request)
        engine.unload()
        engine.unload()
        if (!File(request.audio.filePath).exists()) issues += "engine deleted the request's audio file; the session owns it"
        return issues
    }

    public fun checkDescriptor(engine: SpeechEngine, location: ProcessingLocation): List<String> =
        buildList {
            val descriptor = engine.descriptor
            if (!DiagnosticValue.isSafeIdentifier(descriptor.id.rawValue)) add("engine id ${descriptor.id} is not a stable identifier")
            if (descriptor.location != location) add("engine does not run where it says (${descriptor.location})")
            if (descriptor.supportedLanguages.isEmpty()) add("engine lists no supported language")
        }

    private suspend fun checkRefuses(engine: SpeechEngine, availability: EngineAvailability, request: RecognitionRequest): List<String> =
        try {
            engine.recognize(request) {}
            listOf("engine returned a transcript while ${availability.identifier}")
        } catch (failure: RecognitionFailure) {
            if (failure.error == availability.recognitionError) emptyList()
            else listOf("engine threw ${failure.error.identifier} while ${availability.identifier}")
        }

    private suspend fun checkRecognition(engine: SpeechEngine, request: RecognitionRequest): List<String> {
        val transcript: Transcript =
            try {
                engine.recognize(request) {}
            } catch (failure: RecognitionFailure) {
                val withoutSpeech = setOf(RecognitionError.NoSpeechDetected, RecognitionError.SilentAudio)
                return if (failure.error in withoutSpeech) emptyList() else listOf("ready engine failed with ${failure.error.identifier}")
            }
        return buildList {
            if (transcript.engine != engine.descriptor.id) add("transcript names engine ${transcript.engine}")
            if (!engine.descriptor.supports(transcript.language)) add("transcript language is not one the engine supports")
            if (abs(transcript.audioDurationSeconds - request.audio.durationSeconds) > 0.5) add("audio duration does not match")
            if (transcript.processingDurationSeconds < 0) add("negative processing duration")
            for (segment in transcript.segments) {
                segment.confidence?.let { if (it !in 0.0..1.0) add("segment confidence outside 0...1") }
                segment.startSeconds?.let { if (it < 0) add("segment starts before the recording") }
                segment.durationSeconds?.let { if (it < 0) add("segment has negative duration") }
            }
        }
    }

    private suspend fun checkCancelledBeforeStart(engine: SpeechEngine, request: RecognitionRequest): List<String> =
        try {
            withTimeout(CANCELLATION_DEADLINE) {
                coroutineScope {
                    // The coroutine cancels itself before it calls the engine, so a fast engine
                    // cannot finish first (the Swift contract does the same).
                    val job =
                        async {
                            coroutineContext.job.cancel()
                            engine.recognize(request) {}
                        }
                    try {
                        job.await()
                        listOf("engine returned a transcript after cancellation")
                    } catch (_: CancellationException) {
                        emptyList()
                    } catch (failure: RecognitionFailure) {
                        val allowed = setOf(RecognitionError.Cancelled, engine.availability().recognitionError)
                        if (failure.error in allowed) emptyList() else listOf("cancelled engine threw ${failure.error.identifier}")
                    }
                }
            }
        } catch (_: kotlinx.coroutines.TimeoutCancellationException) {
            listOf("engine took longer than $CANCELLATION_DEADLINE to stop after cancellation")
        }
}
