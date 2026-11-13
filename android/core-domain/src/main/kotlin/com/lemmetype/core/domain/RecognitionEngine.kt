package com.lemmetype.core.domain

/** A stable engine id, for example `whisper`. */
@JvmInline
public value class RecognitionEngineId(public val rawValue: String) {
    public val isCloud: Boolean get() = this == CLOUD

    override fun toString(): String = rawValue

    public companion object {
        public val WHISPER: RecognitionEngineId = RecognitionEngineId("whisper")
        public val CLOUD: RecognitionEngineId = RecognitionEngineId("cloud")
    }
}

public enum class ProcessingLocation { ON_DEVICE, CLOUD }

/** What an engine can be asked to do. Raw values match Swift `RecognitionTask`. */
public enum class RecognitionTask(public val rawValue: String) {
    TRANSCRIBE("transcribe"),
    TRANSLATE_TO_ENGLISH("translate-to-english"),
}

public enum class EngineCapability { PARTIAL_RESULTS, SEGMENT_TIMINGS, CONFIDENCE, PROGRESS, LANGUAGE_DETECTION }

public sealed interface AssetRequirement {
    public data object None : AssetRequirement

    public data class Downloadable(val asset: ModelAssetId) : AssetRequirement
}

/** A language and task an engine is asked to serve. */
public data class RecognitionNeed(
    /** A BCP 47 identifier or [SpokenLanguages.AUTOMATIC]. */
    val language: String,
    val task: RecognitionTask = RecognitionTask.TRANSCRIBE,
)

public data class EngineDescriptor(
    val id: RecognitionEngineId,
    val location: ProcessingLocation = ProcessingLocation.ON_DEVICE,
    /** BCP 47 identifiers such as `en-US`, or bare codes such as `en`. */
    val supportedLanguages: List<String>,
    val assets: AssetRequirement,
    val capabilities: Set<EngineCapability> = emptySet(),
    val tasks: Set<RecognitionTask> = setOf(RecognitionTask.TRANSCRIBE),
) {
    /** Whether `language` (for example `en-GB`) is supported, matching on the code for a bare `en`. */
    public fun supports(language: String): Boolean {
        val code = language.split("-").first()
        return supportedLanguages.any { it == language || it == code }
    }

    /** Whether the engine can take `need`. Says nothing about installed assets. */
    public fun supports(need: RecognitionNeed): Boolean {
        if (need.task !in tasks) return false
        if (SpokenLanguages.isAutomatic(need.language)) return EngineCapability.LANGUAGE_DETECTION in capabilities
        return supports(need.language)
    }
}

public sealed class EngineAvailability(public val identifier: String) {
    public data object Ready : EngineAvailability("ready")

    public data object AssetsMissing : EngineAvailability("assets-missing")

    public data class Unsupported(val reason: UnsupportedReason) : EngineAvailability("unsupported.${reason.rawValue}")

    public data object PermissionUnavailable : EngineAvailability("permission-unavailable")

    public data class Failed(val error: RecognitionError) : EngineAvailability("failed.${error.identifier}")

    public val isReady: Boolean get() = this == Ready

    public val recognitionError: RecognitionError?
        get() =
            when (this) {
                Ready -> null
                AssetsMissing -> RecognitionError.AssetsMissing
                is Unsupported -> RecognitionError.Unsupported(reason)
                PermissionUnavailable -> RecognitionError.PermissionDenied
                is Failed -> error
            }
}

/** A finished recording. The session owns the file; engines never delete it. */
public data class RecordedAudio(
    val filePath: String,
    val durationSeconds: Double,
    val sampleRate: Int = 16_000,
    val channels: Int = 1,
)

public data class RecognitionRequest(
    val audio: RecordedAudio,
    val language: String,
    val task: RecognitionTask = RecognitionTask.TRANSCRIBE,
    /** Vocabulary hints. Never sent off the device. */
    val hints: List<String> = emptyList(),
) {
    val need: RecognitionNeed get() = RecognitionNeed(language, task)

    override fun toString(): String = "RecognitionRequest(language=$language, task=${task.rawValue}, hints=${hints.size})"
}

/** Progress while an engine works. Partial text is shown only and never logged or kept. */
public sealed interface RecognitionUpdate {
    public data class Progress(val fraction: Double) : RecognitionUpdate

    public data class Partial(val text: String) : RecognitionUpdate {
        override fun toString(): String = "Partial(length=${text.length})"
    }
}

public data class TranscriptSegment(
    val text: String,
    val startSeconds: Double? = null,
    val durationSeconds: Double? = null,
    val confidence: Double? = null,
) {
    override fun toString(): String = "TranscriptSegment(length=${text.length})"
}

public data class Transcript(
    val text: String,
    val segments: List<TranscriptSegment> = emptyList(),
    val engine: RecognitionEngineId,
    val language: String,
    val spokenLanguage: String? = null,
    val audioDurationSeconds: Double,
    val processingDurationSeconds: Double,
) {
    val isEmpty: Boolean get() = text.isBlank()

    // Dictated text must never reach a log through toString().
    override fun toString(): String =
        "Transcript(engine=$engine, language=$language, length=${text.length}, segments=${segments.size})"
}

/**
 * A local speech-recognition engine, the Kotlin form of Swift `SpeechRecognitionEngine`.
 *
 * Contract (checked for every engine by `SpeechEngineContract` in core-testing):
 * - **Local only.** No network while preparing or recognising.
 * - **Availability first.** When [availability] is not ready, [recognize] throws
 *   [RecognitionFailure] with that availability's error and never returns a transcript.
 * - **Cancellation.** Cancelling the calling coroutine stops the work promptly; no transcript
 *   is returned and no update is sent afterwards. [RecognitionRunner] enforces the last part.
 * - **No retention.** The engine keeps no audio or text after [recognize] returns and never
 *   deletes the request's audio file.
 */
public interface SpeechEngine {
    public val descriptor: EngineDescriptor

    /** Current availability. Must not prompt for permissions or download anything. */
    public suspend fun availability(): EngineAvailability

    /** Availability for one language and task. */
    public suspend fun availability(need: RecognitionNeed): EngineAvailability =
        if (descriptor.supports(need)) availability() else EngineAvailability.Unsupported(UnsupportedReason.LANGUAGE)

    /** Optional warm-up, for example loading a model. Safe to call repeatedly. */
    public suspend fun prepare() {}

    /** Recognises the whole request. Throws [RecognitionFailure] for expected failures. */
    public suspend fun recognize(request: RecognitionRequest, updates: (RecognitionUpdate) -> Unit): Transcript

    /** Releases memory held by [prepare]. Safe to call at any time. */
    public suspend fun unload() {}
}
