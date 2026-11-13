package com.lemmetype.core.domain

/** Where a dictation session is. Every state is visible to the user. Names match the shared fixture. */
public sealed class RecorderState(public val name: String) {
    public data object Idle : RecorderState("idle")

    /** Starting the microphone. */
    public data object Preparing : RecorderState("preparing")

    public data object Recording : RecorderState("recording")

    /** Finalising the recording. */
    public data object Stopping : RecorderState("stopping")

    /** Recognising, writing, and delivering the text. */
    public data object Processing : RecorderState("processing")

    public data object Completed : RecorderState("completed")

    public data object Cancelled : RecorderState("cancelled")

    public data class Failed(val error: AudioCaptureError) : RecorderState("failed")

    /** The user must choose what to do; the recording is kept until they decide. */
    public data class NeedsAttention(val issue: DictationIssue) : RecorderState("needs-attention")

    /** The microphone may be in use. */
    public val isCapturing: Boolean get() = this == Preparing || this == Recording || this == Stopping

    /** Finished; the next activation starts a new session. */
    public val isFinished: Boolean get() = this == Completed || this == Cancelled || this is Failed || this is NeedsAttention
}

public sealed class RecorderEvent(public val name: String) {
    public data object Activate : RecorderEvent("activate")

    public data object CaptureStarted : RecorderEvent("capture-started")

    public data object StopRequested : RecorderEvent("stop-requested")

    public data object CaptureFinished : RecorderEvent("capture-finished")

    public data object ProcessingFinished : RecorderEvent("processing-finished")

    public data object Cancel : RecorderEvent("cancel")

    public data class Fail(val error: AudioCaptureError) : RecorderEvent("fail")

    /** Processing needs a decision from the user. */
    public data class ProcessingNeedsAttention(val issue: DictationIssue) : RecorderEvent("processing-needs-attention")

    /** The user chose to process the kept recording again. */
    public data object Retry : RecorderEvent("retry")

    /** The finished state has been dismissed. */
    public data object Reset : RecorderEvent("reset")
}

/**
 * The recorder's single source of truth, a port of Swift `RecorderStateMachine`. Every
 * transition not explicitly allowed is rejected, so overlapping or out-of-order events cannot
 * leave the microphone running. `shared/fixtures/recorder-transitions.json` lists all pairs.
 */
public class RecorderStateMachine {
    public var state: RecorderState = RecorderState.Idle
        private set

    /** Applies `event` and returns true, or returns false and leaves the state unchanged. */
    public fun handle(event: RecorderEvent): Boolean {
        val next = transition(state, event) ?: return false
        state = next
        return true
    }

    public companion object {
        @Suppress("CyclomaticComplexMethod")
        public fun transition(state: RecorderState, event: RecorderEvent): RecorderState? =
            when {
                state == RecorderState.Idle && event == RecorderEvent.Activate -> RecorderState.Preparing
                state == RecorderState.Preparing && event == RecorderEvent.CaptureStarted -> RecorderState.Recording
                state == RecorderState.Recording && event == RecorderEvent.StopRequested -> RecorderState.Stopping
                state == RecorderState.Stopping && event == RecorderEvent.CaptureFinished -> RecorderState.Processing
                state == RecorderState.Processing && event == RecorderEvent.ProcessingFinished -> RecorderState.Completed
                // The user resolved an issue themselves (for example Copy).
                state is RecorderState.NeedsAttention && event == RecorderEvent.ProcessingFinished -> RecorderState.Completed
                state == RecorderState.Processing && event is RecorderEvent.ProcessingNeedsAttention ->
                    RecorderState.NeedsAttention(event.issue)
                // Refused before the microphone starts (for example a language that is not ready).
                state == RecorderState.Preparing && event is RecorderEvent.ProcessingNeedsAttention ->
                    RecorderState.NeedsAttention(event.issue)
                state is RecorderState.NeedsAttention && event == RecorderEvent.Retry -> RecorderState.Processing
                event == RecorderEvent.Cancel &&
                    (state == RecorderState.Preparing || state == RecorderState.Recording ||
                        state == RecorderState.Processing || state is RecorderState.NeedsAttention) ->
                    RecorderState.Cancelled
                event is RecorderEvent.Fail &&
                    (state == RecorderState.Preparing || state == RecorderState.Recording ||
                        state == RecorderState.Stopping || state == RecorderState.Processing) ->
                    RecorderState.Failed(event.error)
                state.isFinished && event == RecorderEvent.Reset -> RecorderState.Idle
                state.isFinished && event == RecorderEvent.Activate -> RecorderState.Preparing
                else -> null
            }
    }
}
