import Foundation

/// The versioned file format of a personalization library, used by the local
/// store and by export/import (E4-S1, E4-S8). Readable JSON; keys never change
/// within a format version.
public struct PersonalizationArchive: Codable, Equatable, Sendable {
    /// The format this build writes. Files with a higher version are refused,
    /// never rewritten.
    public static let currentFormatVersion = 1
    /// Identifies the file as LemmeType's.
    public static let formatName = "com.lemmetype.personalization"

    public var format: String
    public var formatVersion: Int
    public var vocabulary: [VocabularyEntry]
    public var replacements: [Replacement]
    public var snippets: [Snippet]
    /// Custom modes (E4-S5); optional so earlier files still decode.
    public var modes: [DictationMode]
    /// Per-app mode rules (E4-S7).
    public var appRules: [AppModeRule]

    public init(_ library: PersonalizationLibrary) {
        format = Self.formatName
        formatVersion = Self.currentFormatVersion
        vocabulary = library.vocabulary
        replacements = library.replacements
        snippets = library.snippets
        modes = library.modes
        appRules = library.appRules
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        vocabulary = try container.decodeIfPresent([VocabularyEntry].self, forKey: .vocabulary) ?? []
        replacements = try container.decodeIfPresent([Replacement].self, forKey: .replacements) ?? []
        snippets = try container.decodeIfPresent([Snippet].self, forKey: .snippets) ?? []
        modes = try container.decodeIfPresent([DictationMode].self, forKey: .modes) ?? []
        appRules = try container.decodeIfPresent([AppModeRule].self, forKey: .appRules) ?? []
    }

    /// The validated library.
    public func library() throws(PersonalizationError) -> PersonalizationLibrary {
        try PersonalizationLibrary(
            vocabulary: vocabulary, replacements: replacements, snippets: snippets, modes: modes, appRules: appRules)
    }

    /// Pretty-printed JSON with sorted keys, so exports diff cleanly.
    public func encoded() throws(PersonalizationError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(self)
        } catch {
            throw .storageFailure
        }
    }

    /// Decodes and validates a file. Not LemmeType JSON → `invalidFile`;
    /// a newer format → `unsupportedVersion`; any invalid item → its error.
    public static func decode(_ data: Data) throws(PersonalizationError) -> PersonalizationLibrary {
        let header: Header
        do {
            header = try JSONDecoder().decode(Header.self, from: data)
        } catch {
            throw .invalidFile
        }
        guard header.format == formatName else { throw .invalidFile }
        guard header.formatVersion <= currentFormatVersion, header.formatVersion >= 1 else {
            throw .unsupportedVersion
        }
        let archive: PersonalizationArchive
        do {
            archive = try JSONDecoder().decode(PersonalizationArchive.self, from: data)
        } catch {
            throw .invalidFile
        }
        return try archive.library()
    }

    private struct Header: Decodable {
        let format: String
        let formatVersion: Int
    }
}
