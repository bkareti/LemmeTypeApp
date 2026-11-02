/// Word error rate for accuracy benchmarks: word-level edit distance between
/// a reference and a hypothesis, divided by the reference length. Both are
/// normalized by ``TranscriptNormalizer`` first, so case and punctuation are
/// ignored. Computed in memory; neither text is stored.
public enum WordErrorRate {
    public static func of(reference: String, hypothesis: String) -> Double {
        alignment(reference: reference, hypothesis: hypothesis).errorRate
    }

    public static func alignment(reference: String, hypothesis: String) -> EditAlignment {
        EditAlignment.align(
            reference: TranscriptNormalizer.words(reference), hypothesis: TranscriptNormalizer.words(hypothesis))
    }
}
