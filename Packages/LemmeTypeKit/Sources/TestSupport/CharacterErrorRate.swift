/// Character error rate: edit distance over Unicode scalars of the normalized
/// texts (``TranscriptNormalizer``), single spaces between words included,
/// divided by the reference length. Fairer than word error rate for Telugu,
/// Kannada, Tamil, and Hindi, where one long word can hold what English says
/// in several and one wrong vowel sign would otherwise fail the whole word.
/// Computed in memory; neither text is stored.
public enum CharacterErrorRate {
    public static func of(reference: String, hypothesis: String) -> Double {
        alignment(reference: reference, hypothesis: hypothesis).errorRate
    }

    public static func alignment(reference: String, hypothesis: String) -> EditAlignment {
        EditAlignment.align(reference: scalars(reference), hypothesis: scalars(hypothesis))
    }

    static func scalars(_ text: String) -> [Unicode.Scalar] {
        Array(TranscriptNormalizer.normalize(text).unicodeScalars)
    }
}
