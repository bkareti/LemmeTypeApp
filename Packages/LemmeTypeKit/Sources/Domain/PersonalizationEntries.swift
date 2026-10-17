import Foundation

/// A word or name the user wants spelled their way (E4-S1). `soundsLike`
/// holds spellings an engine may produce instead ("lemme type").
///
/// Personalization entries are user content: their descriptions are redacted
/// so interpolation into a log or error can never reveal them (ADR 0020).
public struct VocabularyEntry: Identifiable, Equatable, Codable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let id: UUID
    public var term: String
    public var soundsLike: [String]

    public init(id: UUID = UUID(), term: String, soundsLike: [String] = []) {
        self.id = id
        self.term = term
        self.soundsLike = soundsLike
    }

    public var description: String { "VocabularyEntry(redacted)" }
    public var debugDescription: String { description }
}

/// A spoken phrase and the text written instead (E4-S2).
public struct Replacement: Identifiable, Equatable, Codable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let id: UUID
    public var spoken: String
    public var written: String

    public init(id: UUID = UUID(), spoken: String, written: String) {
        self.id = id
        self.spoken = spoken
        self.written = written
    }

    public var description: String { "Replacement(redacted)" }
    public var debugDescription: String { description }
}

/// Saved text inserted when the whole utterance is its trigger (E4-S3).
public struct Snippet: Identifiable, Equatable, Codable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let id: UUID
    public var trigger: String
    /// Delivered exactly as written, line breaks included.
    public var expansion: String

    public init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }

    public var description: String { "Snippet(redacted)" }
    public var debugDescription: String { description }
}

/// Comparison and cleanup rules shared by validation, matching, and import.
public enum PersonalizationText {
    /// Trims and collapses every run of whitespace (including line breaks) to one space.
    public static func normalizedPhrase(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The case-insensitive key two phrases are compared by.
    public static func key(_ text: String) -> String {
        normalizedPhrase(text).lowercased()
    }
}
