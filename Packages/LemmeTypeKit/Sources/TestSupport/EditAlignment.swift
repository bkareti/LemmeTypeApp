/// The minimum edits that turn a reference sequence into a hypothesis
/// (Levenshtein), split by kind. Word and character error rates and the
/// hallucination checks are all built from it.
public struct EditAlignment: Codable, Equatable, Sendable {
    public let referenceLength: Int
    public let substitutions: Int
    public let deletions: Int
    /// Units in the hypothesis that the reference does not have: text that was never said.
    public let insertions: Int

    public init(referenceLength: Int, substitutions: Int, deletions: Int, insertions: Int) {
        self.referenceLength = referenceLength
        self.substitutions = substitutions
        self.deletions = deletions
        self.insertions = insertions
    }

    public var edits: Int { substitutions + deletions + insertions }

    /// Edits ÷ reference length. An empty reference scores 0 against an empty
    /// hypothesis and 1 against anything else.
    public var errorRate: Double {
        guard referenceLength > 0 else { return edits == 0 ? 0 : 1 }
        return Double(edits) / Double(referenceLength)
    }

    /// Insertions ÷ reference length, with the same empty-reference rule.
    public var insertionRate: Double {
        guard referenceLength > 0 else { return insertions == 0 ? 0 : 1 }
        return Double(insertions) / Double(referenceLength)
    }

    public static func align<Element: Equatable>(reference: [Element], hypothesis: [Element]) -> EditAlignment {
        // One row of cells; among equal totals the first candidate wins, so the split is deterministic.
        var previous = (0...hypothesis.count).map { Cell(insertions: $0) }
        for (row, expected) in reference.enumerated() {
            var current = [Cell(deletions: row + 1)]
            current.reserveCapacity(hypothesis.count + 1)
            for (column, actual) in hypothesis.enumerated() {
                var best = previous[column]
                if expected != actual { best.substitutions += 1 }
                var delete = previous[column + 1]
                delete.deletions += 1
                var insert = current[column]
                insert.insertions += 1
                if delete.total < best.total { best = delete }
                if insert.total < best.total { best = insert }
                current.append(best)
            }
            previous = current
        }
        let last = previous[hypothesis.count]
        return EditAlignment(
            referenceLength: reference.count, substitutions: last.substitutions, deletions: last.deletions,
            insertions: last.insertions)
    }

    private struct Cell {
        var substitutions = 0
        var deletions = 0
        var insertions = 0

        var total: Int { substitutions + deletions + insertions }
    }
}
