import Foundation

/// How formal the rewritten text sounds (E10-S1). Raw values are stable.
public enum Tone: String, CaseIterable, Codable, Sendable {
    /// Keep the speaker's own tone.
    case neutral
    case professional
    case friendly
    case casual
}

/// The shape of the rewritten text (E10-S1). Raw values are stable.
public enum WritingFormat: String, CaseIterable, Codable, Sendable {
    /// Ordinary sentences; nothing is added.
    case plainText = "plain-text"
    /// A short chat message.
    case message
    /// A short email with a generic greeting and sign-off.
    case email
    /// One idea per line.
    case bulletList = "bullet-list"
}

/// How much the rewrite may shorten the text (E10-S1). Raw values are stable.
public enum LengthPreference: String, CaseIterable, Codable, Sendable {
    case original
    /// Remove filler and repetition; keep every fact.
    case concise
}

/// The opt-in tone, format, and length a mode applies to newly dictated text
/// (E10-S1, docs/decisions/0024-tone-and-style-rewriting.md). The choices are
/// independent. The default, Neutral + Plain text + Original with grammar
/// correction off, means *no rewrite*: the model is never called for it.
public struct StyleOptions: Equatable, Codable, Sendable {
    public var tone: Tone
    public var format: WritingFormat
    public var length: LengthPreference
    /// Correct grammar, spelling, and punctuation while keeping the speaker's words (E12-S3).
    public var correctsGrammar: Bool

    public init(
        tone: Tone = .neutral, format: WritingFormat = .plainText, length: LengthPreference = .original,
        correctsGrammar: Bool = false
    ) {
        self.tone = tone
        self.format = format
        self.length = length
        self.correctsGrammar = correctsGrammar
    }

    public static let none = StyleOptions()

    /// No choice changes anything, so no rewrite runs.
    public var isNone: Bool { self == .none }

    /// Grammar correction is the only change: the speaker's wording stays.
    public var isGrammarOnly: Bool {
        correctsGrammar && tone == .neutral && format == .plainText && length == .original
    }

    // Tolerant decoding: a missing key is the default for that choice.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tone = try container.decodeIfPresent(Tone.self, forKey: .tone) ?? .neutral
        format = try container.decodeIfPresent(WritingFormat.self, forKey: .format) ?? .plainText
        length = try container.decodeIfPresent(LengthPreference.self, forKey: .length) ?? .original
        correctsGrammar = try container.decodeIfPresent(Bool.self, forKey: .correctsGrammar) ?? false
    }

    /// Stable lowercase name for diagnostics, for example `professional-email-concise`,
    /// with `-grammar` added only when grammar correction is on.
    public var identifier: String {
        guard !isNone else { return "none" }
        let base = [tone.rawValue, format.rawValue, length.rawValue].joined(separator: "-")
        return correctsGrammar ? base + "-grammar" : base
    }
}

/// The fixed instruction sent to the on-device model for a style (E10-S3).
/// Built only from the enumerated choices, never from dictated text, so the
/// wording is deterministic and cannot be changed by what the user says.
public enum StyleInstruction {
    /// `nil` when ``StyleOptions/isNone``.
    public static func make(_ options: StyleOptions) -> String? {
        guard !options.isNone else { return nil }
        var sentences = [opening(options)]
        if options.length == .concise {
            sentences.append("Make it shorter by removing filler and repetition, but keep every fact.")
        }
        sentences.append(
            "Keep every name, number, date, negation (such as \"not\" or \"never\"), and commitment exactly as stated.")
        sentences.append("Do not add facts, names, recipients, numbers, dates, or links that are not in the passage.")
        return sentences.joined(separator: " ")
    }

    private static func opening(_ options: StyleOptions) -> String {
        if options.isGrammarOnly {
            return "Correct the grammar, spelling, and punctuation of the passage. "
                + "Change only what is wrong, and keep the speaker's own words and word order everywhere else."
        }
        let rewrite = "Rewrite the passage \(manner(options))."
        return options.correctsGrammar ? rewrite + " Also correct its grammar, spelling, and punctuation." : rewrite
    }

    private static func manner(_ options: StyleOptions) -> String {
        var parts: [String] = []
        switch options.tone {
        case .neutral: break
        case .professional: parts.append("in a professional, polite tone")
        case .friendly: parts.append("in a warm, friendly tone")
        case .casual: parts.append("in a relaxed, casual tone")
        }
        switch options.format {
        case .plainText:
            parts.append("as plain sentences, without lists or headings")
        case .message:
            parts.append("as a short chat message")
        case .email:
            parts.append(
                "as a short email without a subject line, with a greeting and a sign-off such as \"Thanks,\"; greet a person only by a "
                    + "name that appears in the passage, and never add a recipient or sender name that is not in it")
        case .bulletList:
            parts.append("as a bulleted list with one idea per line, each line starting with \"- \"")
        }
        return parts.joined(separator: " ")
    }
}
