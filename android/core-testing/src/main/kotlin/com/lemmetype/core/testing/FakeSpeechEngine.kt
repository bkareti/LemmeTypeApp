package com.lemmetype.core.testing

import com.lemmetype.core.domain.AssetRequirement
import com.lemmetype.core.domain.EngineAvailability
import com.lemmetype.core.domain.EngineCapability
import com.lemmetype.core.domain.EngineDescriptor
import com.lemmetype.core.domain.RecognitionEngineId
import com.lemmetype.core.domain.RecognitionError
import com.lemmetype.core.domain.RecognitionFailure
import com.lemmetype.core.domain.RecognitionRequest
import com.lemmetype.core.domain.RecognitionUpdate
import com.lemmetype.core.domain.SpeechEngine
import com.lemmetype.core.domain.Transcript
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlin.time.Duration

/** A scripted engine for tests: fixed text, availability, delay, and updates (Swift `FakeRecognitionEngine`). */
public class FakeSpeechEngine(
    id: RecognitionEngineId = RecognitionEngineId.WHISPER,
    public var availability: EngineAvailability = EngineAvailability.Ready,
    public var text: String = "Hello from the fake engine.",
    public var failure: RecognitionError? = null,
    public var work: Duration = Duration.ZERO,
    public var updates: List<RecognitionUpdate> = listOf(RecognitionUpdate.Progress(0.5)),
    /** Send these updates after the work, to test that late updates are dropped. */
    public var lateUpdates: List<RecognitionUpdate> = emptyList(),
    /** Throw an unexpected exception instead of a [RecognitionFailure]. */
    public var crash: Boolean = false,
    supportedLanguages: List<String> = listOf("en"),
    capabilities: Set<EngineCapability> = setOf(EngineCapability.PROGRESS),
) : SpeechEngine {
    override val descriptor: EngineDescriptor =
        EngineDescriptor(id = id, supportedLanguages = supportedLanguages, assets = AssetRequirement.None, capabilities = capabilities)

    public var recognizeCalls: Int = 0
        private set
    public var unloadCalls: Int = 0
        private set

    override suspend fun availability(): EngineAvailability = availability

    override suspend fun recognize(request: RecognitionRequest, updates: (RecognitionUpdate) -> Unit): Transcript {
        recognizeCalls++
        currentCoroutineContext().ensureActive()
        availability.recognitionError?.let { throw RecognitionFailure(it) }
        this.updates.forEach(updates)
        delay(work)
        lateUpdates.forEach(updates)
        if (crash) throw IllegalStateException("fake engine crashed")
        failure?.let { throw RecognitionFailure(it) }
        return Transcript(
            text = text,
            engine = descriptor.id,
            language = request.language,
            audioDurationSeconds = request.audio.durationSeconds,
            processingDurationSeconds = work.inWholeMilliseconds / 1000.0,
        )
    }

    override suspend fun unload() {
        unloadCalls++
    }
}
