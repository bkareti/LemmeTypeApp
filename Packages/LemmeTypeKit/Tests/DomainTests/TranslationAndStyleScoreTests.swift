import Domain
import TestSupport
import Testing

/// chrF, the translation meaning checks, and the rule-checkable parts of a style rewrite.
struct TranslationAndStyleScoreTests {
    @Test func chrFMatchesAWorkedExample() {
        // "thecat" against "thehat" (whitespace removed). Per order, F with β = 2 equals P = R here:
        // 1-grams 5/6, 2-grams 3/5, 3-grams 1/4, 4- to 6-grams 0. The same example is in
        // scripts/tests/test-evaluation-report.py, so both implementations agree.
        let statistics = CharacterNGramStatistics.of(reference: "the cat", hypothesis: "the hat")
        #expect(statistics.matches == [5, 3, 1, 0, 0, 0])
        #expect(statistics.reference == [6, 5, 4, 3, 2, 1])
        #expect(abs(statistics.score - 100 * (5.0 / 6 + 3.0 / 5 + 1.0 / 4) / 6) < 1e-9)
    }

    @Test func chrFEdgesAndPooling() {
        #expect(CharacterNGramStatistics.of(reference: "Ship it.", hypothesis: "Ship it.").score == 100)
        #expect(CharacterNGramStatistics.of(reference: "", hypothesis: "").score == 100)
        #expect(CharacterNGramStatistics.of(reference: "ship", hypothesis: "").score == 0)
        let pooled =
            CharacterNGramStatistics.of(reference: "ab", hypothesis: "ab")
            + CharacterNGramStatistics.of(reference: "cd", hypothesis: "xy")
        #expect(pooled.matches == [2, 1, 0, 0, 0, 0])
        #expect(pooled.hypothesis == [4, 2, 0, 0, 0, 0])
    }

    @Test func aTranslationThatDropsANegationOrChangesANumberIsFlagged() {
        let reference = "I will not come on 12 March."
        #expect(
            TranslationScore.score(englishReference: reference, translation: "I will come on twelve March").violations
                == ["negation-changed"])
        #expect(
            TranslationScore.score(englishReference: reference, translation: "I won't come on 13 March").violations
                == ["number-changed"])
        let kept = TranslationScore.score(englishReference: reference, translation: "I will not come on twelve March")
        #expect(kept.violations.isEmpty)
        #expect(kept.chrF > 50)
    }

    @Test func aBulletRewriteThatShortensFollowsItsStyle() {
        let review = DictationReview(
            text: "- Ship it\n- Call Ana", original: "ship it and call Ana", language: "en",
            style: StyleOptions(format: .bulletList, length: .concise))
        let result = StyleResult.of(review)

        #expect(result.applied)
        #expect(result.notice == nil)
        #expect(result.format == .followed)
        #expect(result.length == .followed)
        #expect(result.violations.isEmpty)
        #expect(result.style == "neutral-bullet-list-concise")
    }

    @Test func formatAndLengthAreCheckedOnlyWhereARuleExists() {
        let notBullets = StyleResult.of(
            DictationReview(
                text: "Ship it and call Ana.", original: "ship it and call Ana", language: "en",
                style: StyleOptions(format: .bulletList)))
        #expect(notBullets.format == .notFollowed)
        #expect(notBullets.length == .notChecked)

        let email = StyleResult.of(
            DictationReview(
                text: "Hi Ana,\nPlease ship it.", original: "ship it", language: "en",
                style: StyleOptions(tone: .professional, format: .email)))
        #expect(email.format == .notChecked)
    }

    @Test func anOriginalOfferedWithANoticeIsNotApplied() {
        let result = StyleResult.of(
            DictationReview(
                text: "ship it", original: "ship it", language: "en", style: StyleOptions(tone: .casual),
                notice: .failed))
        #expect(!result.applied)
        #expect(result.notice == RewriteNotice.failed.identifier)
        #expect(result.format == .notChecked)
    }
}
