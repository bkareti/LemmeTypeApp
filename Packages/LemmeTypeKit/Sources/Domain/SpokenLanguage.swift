import Foundation

/// A language the user can dictate in (E9-S1, docs/decisions/0023-multilingual-dictation.md).
public struct SpokenLanguage: Identifiable, Equatable, Sendable {
    /// ISO 639-1 code, the part before any region: `"hi"`.
    public let code: String
    public let englishName: String
    /// The language's own name, shown next to the localized one.
    public let nativeName: String
    /// The value stored in settings. English keeps the long-standing `en-US`.
    public let settingValue: String

    public var id: String { code }
}

/// The languages LemmeType offers, and the special value for detection.
///
/// A language is listed here only so it can be *evaluated*; whether it is
/// called supported is decided by ``LanguageSupportMatrix``.
public enum SpokenLanguages {
    /// The stored value that asks the engine to detect the language.
    public static let automatic = "auto"

    public static let english = SpokenLanguage(
        code: "en", englishName: "English", nativeName: "English", settingValue: "en-US")
    public static let hindi = SpokenLanguage(
        code: "hi", englishName: "Hindi", nativeName: "हिन्दी", settingValue: "hi")
    public static let telugu = SpokenLanguage(
        code: "te", englishName: "Telugu", nativeName: "తెలుగు", settingValue: "te")

    /// Every selectable language. Tamil, Malayalam, and Kannada are the next
    /// candidates and stay out until they are evaluated.
    public static let all: [SpokenLanguage] = [english, hindi, telugu]

    /// The languages automatic detection chooses between.
    public static var detectionCandidates: [String] { all.map(\.code) }

    /// The language for a stored value such as `"en-GB"` or `"hi"`; `nil` for
    /// `auto` and for languages that are not offered.
    public static func language(for identifier: String) -> SpokenLanguage? {
        let code = code(of: identifier)
        return all.first { $0.code == code }
    }

    /// The language part of a BCP 47 identifier, lowercased: `"en-GB"` → `"en"`.
    public static func code(of identifier: String) -> String {
        let base = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? identifier
        return base.lowercased()
    }

    public static func isEnglish(_ identifier: String) -> Bool {
        code(of: identifier) == "en"
    }

    public static func isAutomatic(_ identifier: String) -> Bool {
        identifier == automatic
    }
}

/// What the user gets back from speech (E9-S3). Independent of the language
/// that was spoken. Raw values are stable.
public enum SpeechOutput: String, CaseIterable, Codable, Sendable {
    /// The words in the language they were spoken. Never translated.
    case original
    /// English text. Speech in another language is translated.
    case english
}

/// What a recognition request asks the engine to do (E9-S2). Raw values are
/// stable diagnostics identifiers.
public enum RecognitionTask: String, CaseIterable, Codable, Sendable {
    /// Write what was said, in the language it was said.
    case transcribe
    /// Write what was said as English.
    case translateToEnglish = "translate-to-english"
}
