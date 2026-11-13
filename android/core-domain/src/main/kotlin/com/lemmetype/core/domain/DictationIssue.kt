package com.lemmetype.core.domain

/**
 * A processing result that needs the user's decision. The recording is kept until the user
 * acts or discards it. The subset of Swift `DictationIssue` the Android beta uses; the rest
 * (delivery, editing, rewriting, subscription) arrives with the stories that need it.
 */
public sealed class DictationIssue(public val identifier: String) {
    public data class RecognitionFailed(val error: RecognitionError) : DictationIssue(error.identifier)

    /** The chosen engine cannot run (assets, permission, hardware). */
    public data class EngineUnavailable(val engine: RecognitionEngineId, val availability: EngineAvailability) :
        DictationIssue("engine.${availability.identifier}")

    /** No local engine is ready. */
    public data object NoEngineAvailable : DictationIssue("engine.none-available")

    /** A translation to read before it is inserted or copied. */
    public data object ReviewTranslation : DictationIssue("review.translation")

    /** Plain dictated text to read before it is copied, on a platform without insertion. */
    public data object ReviewText : DictationIssue("review.text")
}
