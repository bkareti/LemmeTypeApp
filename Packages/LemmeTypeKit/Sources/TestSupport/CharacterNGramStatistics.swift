import Foundation

/// chrF: how much of a translation's character n-grams (1…6) match the human
/// reference. Unlike word error rate it gives credit for a different but close
/// word form, which matters when the same meaning has several English wordings.
///
/// Definition used here (and by `scripts/evaluation-report.py`): text in NFC
/// with all whitespace removed; for each n with n-grams on both sides,
/// precision P and recall R of the clipped matches and F = (1 + β²)PR ÷ (β²P + R)
/// with β = 2; chrF is 100 × the mean F over those n. Statistics add up across
/// runs, so a corpus score is pooled like word error rate. It follows the chrF
/// paper (Popović 2015); it has not been checked against sacreBLEU's numbers.
public struct CharacterNGramStatistics: Codable, Equatable, Sendable {
    public static let maximumOrder = 6
    public static let beta = 2.0

    /// N-grams of order 1…6 in the hypothesis.
    public var hypothesis: [Int]
    /// N-grams of order 1…6 in the reference.
    public var reference: [Int]
    /// Clipped matches of order 1…6.
    public var matches: [Int]

    public init(hypothesis: [Int], reference: [Int], matches: [Int]) {
        self.hypothesis = hypothesis
        self.reference = reference
        self.matches = matches
    }

    public static let zero = CharacterNGramStatistics(
        hypothesis: Array(repeating: 0, count: maximumOrder), reference: Array(repeating: 0, count: maximumOrder),
        matches: Array(repeating: 0, count: maximumOrder))

    public static func of(reference: String, hypothesis: String) -> CharacterNGramStatistics {
        let expected = scalars(reference)
        let actual = scalars(hypothesis)
        var statistics = zero
        for order in 1...maximumOrder {
            let wanted = ngrams(expected, order)
            let got = ngrams(actual, order)
            statistics.reference[order - 1] = wanted.values.reduce(0, +)
            statistics.hypothesis[order - 1] = got.values.reduce(0, +)
            statistics.matches[order - 1] = got.reduce(0) { $0 + min($1.value, wanted[$1.key] ?? 0) }
        }
        return statistics
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            hypothesis: zip(lhs.hypothesis, rhs.hypothesis).map(+), reference: zip(lhs.reference, rhs.reference).map(+),
            matches: zip(lhs.matches, rhs.matches).map(+))
    }

    /// 0…100. An empty hypothesis for an empty reference scores 100.
    public var score: Double {
        var total = 0.0
        var orders = 0
        for order in 0..<Self.maximumOrder where hypothesis[order] > 0 && reference[order] > 0 {
            let precision = Double(matches[order]) / Double(hypothesis[order])
            let recall = Double(matches[order]) / Double(reference[order])
            let factor = Self.beta * Self.beta
            let denominator = factor * precision + recall
            total += denominator > 0 ? (1 + factor) * precision * recall / denominator : 0
            orders += 1
        }
        if orders == 0 { return reference.allSatisfy { $0 == 0 } && hypothesis.allSatisfy { $0 == 0 } ? 100 : 0 }
        return 100 * total / Double(orders)
    }

    static func scalars(_ text: String) -> [Unicode.Scalar] {
        text.precomposedStringWithCanonicalMapping.unicodeScalars.filter { !$0.properties.isWhitespace }
    }

    static func ngrams(_ scalars: [Unicode.Scalar], _ order: Int) -> [String: Int] {
        guard scalars.count >= order else { return [:] }
        var counts: [String: Int] = [:]
        for start in 0...(scalars.count - order) {
            counts[String(String.UnicodeScalarView(scalars[start..<(start + order)])), default: 0] += 1
        }
        return counts
    }
}
