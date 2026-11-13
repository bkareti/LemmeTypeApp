package com.lemmetype.core.domain

/** Expected audio-capture failures. Identifiers match Swift `AudioCaptureError`. */
public sealed class AudioCaptureError(public val identifier: String) {
    public data object MicrophonePermissionMissing : AudioCaptureError("audio.permission-missing")
    public data object NoInputDevice : AudioCaptureError("audio.no-input-device")
    public data object DeviceDisconnected : AudioCaptureError("audio.device-disconnected")

    /** A call, another app, or the system took the input. */
    public data object Interrupted : AudioCaptureError("audio.interrupted")
    public data object AlreadyCapturing : AudioCaptureError("audio.already-capturing")
    public data object NotCapturing : AudioCaptureError("audio.not-capturing")
    public data class EngineFailure(val code: Int) : AudioCaptureError("audio.engine-failure")
    public data object StorageFailure : AudioCaptureError("audio.storage-failure")

    /** Less free space than [MINIMUM_FREE_BYTES] for the temporary recording. */
    public data object InsufficientStorage : AudioCaptureError("audio.insufficient-storage")

    public companion object {
        /** Recording needs at least this much free space (Swift E5-S6). */
        public const val MINIMUM_FREE_BYTES: Long = 100_000_000
    }
}
