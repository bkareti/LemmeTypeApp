package com.lemmetype.core.domain

import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** How long one recording may run before LemmeType stops it (ADR 0027). */
public data class RecordingLimits(
    /** `null` means no limit. */
    val maximumDuration: Duration?,
) {
    public companion object {
        public val NONE: RecordingLimits = RecordingLimits(null)

        /** Phones: five minutes (Proposed). A forgotten recording must not keep the microphone open. */
        public val HANDHELD: RecordingLimits = RecordingLimits(300.seconds)
    }
}
