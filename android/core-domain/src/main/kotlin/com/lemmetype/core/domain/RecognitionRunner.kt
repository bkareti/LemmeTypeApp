package com.lemmetype.core.domain

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * Runs an engine with the guarantees every caller relies on, whatever the engine does
 * (Swift `RecognitionRunner`):
 * - a request the engine cannot serve, or an engine that is not ready, fails without calling it;
 * - once the calling coroutine is cancelled, no update is forwarded and no transcript is
 *   returned, even if the engine produces one. Cancellation surfaces as Kotlin's
 *   [CancellationException], which keeps structured concurrency intact;
 * - any other unexpected exception from an engine becomes [RecognitionError.EngineFailure] with code -1.
 */
public class RecognitionRunner {
    public suspend fun run(
        engine: SpeechEngine,
        request: RecognitionRequest,
        updates: (RecognitionUpdate) -> Unit = {},
    ): Transcript {
        if (!engine.descriptor.supports(request.need)) {
            throw RecognitionFailure(RecognitionError.Unsupported(UnsupportedReason.LANGUAGE))
        }
        engine.availability(request.need).recognitionError?.let { throw RecognitionFailure(it) }
        currentCoroutineContext().ensureActive()
        val job = currentCoroutineContext()[Job]
        val gate = UpdateGate(updates) { job?.isActive ?: true }
        val transcript =
            try {
                engine.recognize(request, gate::send)
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (failure: RecognitionFailure) {
                currentCoroutineContext().ensureActive()
                throw failure
            } catch (@Suppress("TooGenericExceptionCaught") unexpected: Exception) {
                currentCoroutineContext().ensureActive()
                throw RecognitionFailure(RecognitionError.EngineFailure(code = -1))
            } finally {
                gate.close()
            }
        currentCoroutineContext().ensureActive()
        return transcript
    }
}

/** Forwards updates until closed or the caller is cancelled; afterwards drops them. */
private class UpdateGate(
    private val forward: (RecognitionUpdate) -> Unit,
    private val callerIsActive: () -> Boolean,
) {
    private val lock = Any()
    private var open = true

    fun send(update: RecognitionUpdate) {
        // Forward while holding the lock so close() cannot finish while an update is being delivered.
        synchronized(lock) {
            if (open && callerIsActive()) forward(update)
        }
    }

    fun close() {
        synchronized(lock) { open = false }
    }
}
