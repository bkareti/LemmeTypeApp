import Domain

/// How well a translation to English kept the meaning of the human English
/// reference: chrF, plus the deterministic checks the app's style rewriting
/// already trusts (``PreservationChecker``: numbers, dates, names, negation,
/// commitments, links) after ``NumberNormalizer`` on both sides.
///
/// These are proxies. A dropped number or negation is a meaning error for
/// sure; a passing score does not prove the meaning survived. The human review
/// rubric in `docs/testing/language-support-matrix.md` stays the judge.
public struct TranslationScore: Codable, Equatable, Sendable {
    public let characterNGrams: CharacterNGramStatistics
    /// `PreservationViolation` raw values, in the checker's order.
    public let violations: [String]

    public init(characterNGrams: CharacterNGramStatistics, violations: [String]) {
        self.characterNGrams = characterNGrams
        self.violations = violations
    }

    public var chrF: Double { characterNGrams.score }

    /// Violations that change what was said beyond doubt.
    public static let critical: Set<String> = [
        PreservationViolation.numberChanged.rawValue, PreservationViolation.negationChanged.rawValue,
    ]

    public static func score(englishReference: String, translation: String) -> TranslationScore {
        TranslationScore(
            characterNGrams: .of(reference: englishReference, hypothesis: translation),
            violations: PreservationChecker.violations(
                original: NumberNormalizer.normalize(englishReference),
                rewritten: NumberNormalizer.normalize(translation)
            ).map(\.rawValue))
    }
}
