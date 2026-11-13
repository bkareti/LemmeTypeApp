package com.lemmetype.core.domain

/** Diagnostics categories. Names match Swift `DiagnosticCategory`. */
public enum class DiagnosticCategory(public val rawValue: String) {
    LIFECYCLE("lifecycle"),
    PERMISSIONS("permissions"),
    AUDIO("audio"),
    RECORDER("recorder"),
    RECOGNITION("recognition"),
    MODELS("models"),
    DELIVERY("delivery"),
    EDITING("editing"),
    PERSONALIZATION("personalization"),
}

/**
 * A diagnostics value: identifiers, counts, flags, and durations only. Free text cannot be
 * stored: [id] redacts anything that is not a short lowercase identifier (Swift `DiagnosticValue`).
 */
public sealed interface DiagnosticValue {
    @ConsistentCopyVisibility
    public data class Identifier internal constructor(val value: String) : DiagnosticValue

    public data class Count(val value: Int) : DiagnosticValue

    public data class Flag(val value: Boolean) : DiagnosticValue

    public data class Seconds(val value: Double) : DiagnosticValue

    public companion object {
        public const val REDACTED: String = "redacted"

        public fun id(raw: String): DiagnosticValue = Identifier(if (isSafeIdentifier(raw)) raw else REDACTED)

        /** 1–64 characters of `a-z`, `0-9`, `.`, `_`, `-`, starting with a letter or digit. */
        public fun isSafeIdentifier(raw: String): Boolean {
            if (raw.isEmpty() || raw.length > 64) return false
            val first = raw[0]
            if (first !in 'a'..'z' && first !in '0'..'9') return false
            return raw.all { it in 'a'..'z' || it in '0'..'9' || it == '.' || it == '_' || it == '-' }
        }
    }
}

/** One diagnostics event. The name must be a safe identifier; attribute values are typed. */
public data class DiagnosticEvent(
    val timestampMillis: Long,
    val category: DiagnosticCategory,
    val name: String,
    val attributes: Map<String, DiagnosticValue>,
) {
    init {
        require(DiagnosticValue.isSafeIdentifier(name)) { "Event names are fixed identifiers" }
        require(attributes.keys.all(DiagnosticValue::isSafeIdentifier)) { "Attribute keys are fixed identifiers" }
    }
}

/** Where components send diagnostics. The default discards them. */
public fun interface DiagnosticsRecording {
    public fun record(category: DiagnosticCategory, name: String, attributes: Map<String, DiagnosticValue>)
}

public object DiscardingDiagnostics : DiagnosticsRecording {
    override fun record(category: DiagnosticCategory, name: String, attributes: Map<String, DiagnosticValue>) {}
}
