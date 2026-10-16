/// Word error rate for accuracy benchmarks: word-level edit distance between
/// a reference and a hypothesis, divided by the reference length. Case and
/// punctuation are ignored. Computed in memory; neither text is stored.
public enum WordErrorRate {
    public static func of(reference: String, hypothesis: String) -> Double {
        let expected = words(reference)
        let actual = words(hypothesis)
        guard !expected.isEmpty else { return actual.isEmpty ? 0 : 1 }
        var previous = Array(0...actual.count)
        for (row, word) in expected.enumerated() {
            var current = [row + 1] + [Int](repeating: 0, count: actual.count)
            for (column, candidate) in actual.enumerated() {
                let substitution = previous[column] + (word == candidate ? 0 : 1)
                current[column + 1] = min(substitution, previous[column + 1] + 1, current[column] + 1)
            }
            previous = current
        }
        return Double(previous[actual.count]) / Double(expected.count)
    }

    static func words(_ text: String) -> [String] {
        let normalized = String(
            text.lowercased().map { (character: Character) -> Character in
                character.isLetter || character.isNumber || character == "'" ? character : " "
            })
        return normalized.split(separator: " ").map(String.init)
    }
}
