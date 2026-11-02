import Foundation

/// The one text normalization every accuracy metric uses, so word and
/// character error rates compare the same thing in every language.
///
/// Canonical composition (NFC), so a precomposed and a decomposed vowel sign
/// are equal; zero-width joiners and spaces removed, because engines and human
/// transcribers use them inconsistently in Indic scripts; lower case; curly
/// apostrophes made straight. Every character that is not a letter, digit,
/// combining mark, or apostrophe — punctuation such as the Devanagari danda
/// (।) included — becomes a word break.
public enum TranscriptNormalizer {
    /// Scalars dropped before comparison: zero-width space, non-joiner, joiner, and byte-order mark.
    static let ignoredScalars: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"]

    /// Words separated by single spaces.
    public static func normalize(_ text: String) -> String {
        words(text).joined(separator: " ")
    }

    public static func words(_ text: String) -> [String] {
        var scalars = String.UnicodeScalarView()
        for scalar in text.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            if ignoredScalars.contains(scalar) { continue }
            if scalar == "\u{2019}" || scalar == "\u{2018}" {
                scalars.append("'")
            } else if isWordScalar(scalar) {
                scalars.append(scalar)
            } else {
                scalars.append(" ")
            }
        }
        return String(scalars).split(separator: " ").map(String.init)
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "'" { return true }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }
}
