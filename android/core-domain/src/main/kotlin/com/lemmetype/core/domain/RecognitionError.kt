package com.lemmetype.core.domain

/** Why an engine cannot run here. Raw values are stable diagnostics identifiers. */
public enum class UnsupportedReason(public val rawValue: String) {
    OPERATING_SYSTEM("operating-system"),
    HARDWARE("hardware"),
    INSUFFICIENT_MEMORY("insufficient-memory"),
    LANGUAGE("language"),
    ON_DEVICE_RECOGNITION_UNAVAILABLE("on-device-unavailable"),
}

/**
 * Expected recognition failures, a port of Swift `RecognitionError`.
 * `shared/fixtures/recognition-errors.json` lists the identifiers and retry rule both sides use.
 */
public sealed class RecognitionError(
    /** Stable name used in fixtures (`no-speech-detected`). */
    public val caseName: String,
    public val identifier: String,
    /** Whether running the same engine again could succeed without the user changing anything. */
    public val isRetryable: Boolean,
) {
    /** The session was cancelled; never shown as a failure. */
    public data object Cancelled : RecognitionError("cancelled", "recognition.cancelled", false)
    public data object AssetsMissing : RecognitionError("assets-missing", "recognition.assets-missing", false)
    public data class Unsupported(val reason: UnsupportedReason) :
        RecognitionError("unsupported", "recognition.unsupported", false)
    public data object PermissionDenied : RecognitionError("permission-denied", "recognition.permission-denied", false)
    public data object AudioUnreadable : RecognitionError("audio-unreadable", "recognition.audio-unreadable", true)
    public data object NoSpeechDetected : RecognitionError("no-speech-detected", "recognition.no-speech", false)

    /** A normal-length recording with no sound at all: the microphone is the likely cause. */
    public data object SilentAudio : RecognitionError("silent-audio", "recognition.silent-audio", false)
    public data object ModelLoadFailed : RecognitionError("model-load-failed", "recognition.model-load-failed", true)
    public data object LanguageUncertain : RecognitionError("language-uncertain", "recognition.language-uncertain", false)

    /** The engine reported an error; `code` is its numeric code only. */
    public data class EngineFailure(val code: Int) :
        RecognitionError("engine-failure", "recognition.engine-failure", true)
    public data object CloudOffline : RecognitionError("cloud-offline", "recognition.cloud-offline", true)
    public data object CloudKeyRejected : RecognitionError("cloud-key-rejected", "recognition.cloud-key-rejected", false)
    public data object SubscriptionRequired :
        RecognitionError("subscription-required", "recognition.subscription-required", false)
    public data object CloudRateLimited : RecognitionError("cloud-rate-limited", "recognition.cloud-rate-limited", true)
    public data object CloudQuotaExhausted :
        RecognitionError("cloud-quota-exhausted", "recognition.cloud-quota-exhausted", false)
    public data object CloudServiceFailed :
        RecognitionError("cloud-service-failed", "recognition.cloud-service-failed", true)
    public data object CloudUnavailable : RecognitionError("cloud-unavailable", "recognition.cloud-unavailable", false)
}

/** The exception that carries a [RecognitionError] (Kotlin has no typed throws). */
public class RecognitionFailure(public val error: RecognitionError) : Exception(error.identifier)
