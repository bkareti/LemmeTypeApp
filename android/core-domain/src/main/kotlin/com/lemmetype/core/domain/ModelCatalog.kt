package com.lemmetype.core.domain

@JvmInline
public value class ModelAssetId(public val rawValue: String) {
    override fun toString(): String = rawValue
}

public enum class ModelTier(public val rawValue: String) {
    FASTEST("fastest"),
    BALANCED("balanced"),
    MOST_ACCURATE("most-accurate"),
}

public data class ModelFile(
    val name: String,
    val url: String,
    /** Lowercase hexadecimal SHA-256 of the complete file. */
    val sha256: String,
    val bytes: Long,
)

/** A downloadable model. Device fit is decided per platform and is not part of the asset. */
public data class ModelAsset(
    val id: ModelAssetId,
    val displayName: String,
    val version: String,
    val engine: RecognitionEngineId,
    val files: List<ModelFile>,
    val languages: List<String>,
    val tasks: Set<RecognitionTask>,
    val tier: ModelTier,
    val runtimeMemoryBytes: Long,
    val license: String,
) {
    val downloadBytes: Long get() = files.sumOf { it.bytes }
    val detectsLanguage: Boolean get() = languages.size > 1
}

/**
 * The same Whisper files and SHA-256 pins as Swift `ModelCatalog` (ADR 0012, 0022). Checked
 * against `shared/fixtures/model-catalog.json`, which the Swift tests also check.
 */
public object ModelCatalog {
    public val ALLOWED_HOSTS: Set<String> = setOf("huggingface.co")

    private const val MULTILINGUAL_EVALUATION = "en,hi,te"

    private fun whisper(
        id: String,
        name: String,
        file: String,
        sha256: String,
        bytes: Long,
        tier: ModelTier,
        memory: Long,
        multilingual: Boolean = false,
    ): ModelAsset =
        ModelAsset(
            id = ModelAssetId(id),
            displayName = name,
            version = file.removeSuffix(".bin"),
            engine = RecognitionEngineId.WHISPER,
            files = listOf(ModelFile(file, "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$file", sha256, bytes)),
            languages = if (multilingual) MULTILINGUAL_EVALUATION.split(",") else listOf("en"),
            tasks =
                if (multilingual) {
                    setOf(RecognitionTask.TRANSCRIBE, RecognitionTask.TRANSLATE_TO_ENGLISH)
                } else {
                    setOf(RecognitionTask.TRANSCRIBE)
                },
            tier = tier,
            runtimeMemoryBytes = memory,
            license = "MIT",
        )

    public val WHISPER_TINY_ENGLISH: ModelAsset =
        whisper(
            "whisper-tiny-en", "Whisper Tiny (English)", "ggml-tiny.en.bin",
            "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f", 77_704_715, ModelTier.FASTEST, 273_000_000,
        )
    public val WHISPER_BASE_ENGLISH: ModelAsset =
        whisper(
            "whisper-base-en", "Whisper Base (English)", "ggml-base.en.bin",
            "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002", 147_964_211, ModelTier.BALANCED, 388_000_000,
        )
    public val WHISPER_SMALL_ENGLISH: ModelAsset =
        whisper(
            "whisper-small-en", "Whisper Small (English)", "ggml-small.en.bin",
            "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d", 487_614_201, ModelTier.MOST_ACCURATE,
            852_000_000,
        )
    public val WHISPER_TINY: ModelAsset =
        whisper(
            "whisper-tiny", "Whisper Tiny (Multilingual)", "ggml-tiny.bin",
            "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21", 77_691_713, ModelTier.FASTEST, 273_000_000,
            multilingual = true,
        )
    public val WHISPER_BASE: ModelAsset =
        whisper(
            "whisper-base", "Whisper Base (Multilingual)", "ggml-base.bin",
            "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe", 147_951_465, ModelTier.BALANCED, 388_000_000,
            multilingual = true,
        )
    public val WHISPER_SMALL: ModelAsset =
        whisper(
            "whisper-small", "Whisper Small (Multilingual)", "ggml-small.bin",
            "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b", 487_601_967, ModelTier.MOST_ACCURATE,
            852_000_000, multilingual = true,
        )

    /** English-only first, each fastest first (the Swift order). */
    public val ALL: List<ModelAsset> =
        listOf(WHISPER_TINY_ENGLISH, WHISPER_BASE_ENGLISH, WHISPER_SMALL_ENGLISH, WHISPER_TINY, WHISPER_BASE, WHISPER_SMALL)

    public fun asset(id: ModelAssetId): ModelAsset? = ALL.firstOrNull { it.id == id }

    /** HTTPS on an allowlisted host. Parsed by hand: core modules have no networking imports. */
    public fun isTrustedSource(url: String): Boolean {
        if (!url.startsWith("https://")) return false
        val rest = url.removePrefix("https://")
        val authority = rest.substringBefore('/').substringBefore('?').substringBefore('#')
        if ('@' in authority) return false
        val host = authority.substringBefore(':').lowercase()
        return host in ALLOWED_HOSTS
    }
}
