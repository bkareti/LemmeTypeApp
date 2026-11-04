import Foundation

/// The decoding loop speech models fall into: the same phrase written again
/// and again, far more often than anyone says it (ADR 0028). Pure.
///
/// Words are compared without case and without the punctuation around them,
/// so "Thank you. Thank you. Thank you." is one phrase repeated.
public enum RepetitionLoop {
    /// Copies in a row from which a phrase counts as a loop. People do say a
    /// word or phrase three times ("no, no, no"), so a loop needs more.
    public static let minimumCopies = 4
    /// The longest phrase, in words, that is checked.
    public static let longestPhrase = 8

    /// The run of copies in `text` that repeats most often in a row.
    public struct Run: Equatable, Sendable {
        /// Words in the repeated phrase.
        public let phraseLength: Int
        public let copies: Int

        public init(phraseLength: Int, copies: Int) {
            self.phraseLength = phraseLength
            self.copies = copies
        }
    }

    /// `text` with every loop cut back to its first copy, and how many copies
    /// were cut. Text without a loop comes back unchanged, spacing included.
    public static func collapse(_ text: String) -> (text: String, removedCopies: Int) {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let keys = words.map(key)
        var kept: [String] = []
        var removed = 0
        var index = 0
        while index < words.count {
            if let run = loop(in: keys, at: index) {
                kept += words[index..<(index + run.phraseLength)]
                removed += run.copies - 1
                index += run.phraseLength * run.copies
            } else {
                kept.append(words[index])
                index += 1
            }
        }
        return removed == 0 ? (text, 0) : (kept.joined(separator: " "), removed)
    }

    /// The run with the most copies anywhere in `text` (one copy of a single
    /// word when nothing repeats), for diagnostics and tests.
    public static func longestRun(in text: String) -> Run {
        let keys = text.split(whereSeparator: \.isWhitespace).map { key(String($0)) }
        var longest = Run(phraseLength: 1, copies: keys.isEmpty ? 0 : 1)
        for index in keys.indices {
            for length in 1...longestPhrase {
                let copies = copies(of: length, in: keys, at: index)
                if copies > longest.copies { longest = Run(phraseLength: length, copies: copies) }
            }
        }
        return longest
    }

    /// A loop starting at `index`: the shortest phrase with at least
    /// ``minimumCopies`` copies, so "a a a a" is one word four times, not
    /// "a a" twice.
    private static func loop(in keys: [String], at index: Int) -> Run? {
        for length in 1...longestPhrase {
            let copies = copies(of: length, in: keys, at: index)
            if copies >= minimumCopies { return Run(phraseLength: length, copies: copies) }
        }
        return nil
    }

    private static func copies(of length: Int, in keys: [String], at index: Int) -> Int {
        guard index + length <= keys.count, !keys[index..<(index + length)].contains("") else { return 0 }
        let phrase = keys[index..<(index + length)]
        var copies = 1
        var next = index + length
        while next + length <= keys.count, keys[next..<(next + length)] == phrase {
            copies += 1
            next += length
        }
        return copies
    }

    /// Lower case without surrounding punctuation; empty for punctuation alone.
    private static func key(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }
}
