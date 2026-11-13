package com.lemmetype.core.domain

/** Language identifier helpers, matching Swift `SpokenLanguages`. */
public object SpokenLanguages {
    /** The stored value for automatic detection. */
    public const val AUTOMATIC: String = "auto"

    /** The base code of `en-US` or `te_IN`, lower case. */
    public fun code(identifier: String): String = identifier.split('-', '_').first().lowercase()

    public fun isEnglish(identifier: String): Boolean = code(identifier) == "en"

    public fun isAutomatic(identifier: String): Boolean = identifier == AUTOMATIC
}

/** Which languages a build offers (ADR 0029). The Android beta is [ENGLISH_ONLY]. */
public enum class LanguageScope(public val rawValue: String) {
    ENGLISH_ONLY("english-only"),
    ENGLISH_WITH_CLOUD("english-with-cloud"),
    ALL_LANGUAGES("all-languages"),
    ;

    public fun offers(language: String): Boolean =
        when (this) {
            ALL_LANGUAGES -> true
            ENGLISH_ONLY -> SpokenLanguages.isEnglish(language)
            ENGLISH_WITH_CLOUD -> SpokenLanguages.isEnglish(language) || SpokenLanguages.code(language) == "te"
        }

    /** Whether Settings lists `asset`: English-only builds list only English-only models. */
    public fun lists(asset: ModelAsset): Boolean =
        when (this) {
            ALL_LANGUAGES -> true
            ENGLISH_ONLY, ENGLISH_WITH_CLOUD -> asset.languages.isNotEmpty() && asset.languages.all(SpokenLanguages::isEnglish)
        }
}
