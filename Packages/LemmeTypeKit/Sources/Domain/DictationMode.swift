import Foundation

/// Stable identity of a dictation mode (E4-S5). Built-in raw values never
/// change; custom modes are `custom-<uuid>`. Persisted in preferences and the
/// personalization file.
public struct DictationModeID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let exact = DictationModeID(rawValue: "exact")
    public static let clean = DictationModeID(rawValue: "clean")
    public static let message = DictationModeID(rawValue: "message")

    public static func newCustom() -> DictationModeID {
        DictationModeID(rawValue: "custom-\(UUID().uuidString.lowercased())")
    }

    public var isBuiltIn: Bool { DictationMode.builtIns.contains { $0.id == self } }

    /// The built-in identifier, or `custom`: never a user-chosen value.
    public var diagnosticIdentifier: String { isBuiltIn ? rawValue : "custom" }

    public var description: String { diagnosticIdentifier }
}

/// What happens to a final period (style).
public enum FinalPunctuation: String, CaseIterable, Codable, Sendable {
    /// Whatever the writing mode produced.
    case keep
    /// Drop one final period, as in chat messages. `?` and `!` stay.
    case omit
}

/// Where the text goes (output).
public enum OutputAction: String, CaseIterable, Codable, Sendable {
    /// Insert at the cursor of the app that was active (Accessibility, then
    /// the clipboard fallback policy).
    case insert
    /// Only put the text on the clipboard; the target app is not touched.
    case copy
}

/// A named bundle of transcription, cleanup, style, and output choices
/// (E4-S5, ADR 0021). Value type: the session captures the resolved mode when
/// recording starts.
public struct DictationMode: Identifiable, Equatable, Codable, Sendable {
    public let id: DictationModeID
    public var name: String
    // Transcription. `nil` uses Settings › Dictation.
    public var engine: RecognitionEngineID?
    public var language: String?
    // Cleanup.
    public var writingMode: WritingMode
    /// Clean Writing rules that run, in ``CleanupRule/allCases`` order.
    public var cleanupRules: [CleanupRule]
    // Style.
    /// Vocabulary and replacements (E4-S2).
    public var usesPersonalization: Bool
    /// Snippet triggers (E4-S3).
    public var usesSnippets: Bool
    public var finalPunctuation: FinalPunctuation
    // Output.
    public var output: OutputAction
    /// Add one space after the text so the next dictation can follow on.
    public var appendsSpace: Bool

    public init(
        id: DictationModeID = .newCustom(),
        name: String,
        engine: RecognitionEngineID? = nil,
        language: String? = nil,
        writingMode: WritingMode = .clean,
        cleanupRules: [CleanupRule] = CleanupRule.allCases,
        usesPersonalization: Bool = true,
        usesSnippets: Bool = true,
        finalPunctuation: FinalPunctuation = .keep,
        output: OutputAction = .insert,
        appendsSpace: Bool = false
    ) {
        self.id = id
        self.name = name
        self.engine = engine
        self.language = language
        self.writingMode = writingMode
        self.cleanupRules = cleanupRules
        self.usesPersonalization = usesPersonalization
        self.usesSnippets = usesSnippets
        self.finalPunctuation = finalPunctuation
        self.output = output
        self.appendsSpace = appendsSpace
    }

    public var isBuiltIn: Bool { id.isBuiltIn }

    /// The Clean Writing configuration this mode runs.
    public var cleanupConfiguration: CleanupConfiguration {
        CleanupConfiguration(enabledRules: Set(cleanupRules))
    }

    /// A custom copy with a new identity, for Duplicate.
    public func duplicated(named name: String) -> DictationMode {
        DictationMode(
            name: name, engine: engine, language: language, writingMode: writingMode, cleanupRules: cleanupRules,
            usesPersonalization: usesPersonalization, usesSnippets: usesSnippets, finalPunctuation: finalPunctuation,
            output: output, appendsSpace: appendsSpace)
    }

    // MARK: Built-ins

    /// Epic 2's Exact Dictation, unchanged.
    public static let exact = DictationMode(id: .exact, name: "Exact Dictation", writingMode: .exact)
    /// Epic 2's Clean Writing, unchanged.
    public static let clean = DictationMode(id: .clean, name: "Clean Writing", writingMode: .clean)
    /// Clean Writing without a final period, for chat.
    public static let message = DictationMode(
        id: .message, name: "Message", writingMode: .clean, finalPunctuation: .omit)

    public static let builtIns: [DictationMode] = [exact, clean, message]

    /// The built-in mode matching an Epic 2 writing-mode preference.
    public static func builtIn(for writingMode: WritingMode) -> DictationMode {
        writingMode == .exact ? exact : clean
    }

    public static let maximumNameLength = 40
}

/// "Use this mode in this app" (E4-S7). Bundle identifiers only.
public struct AppModeRule: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var bundleIdentifier: String
    public var mode: DictationModeID

    public init(id: UUID = UUID(), bundleIdentifier: String, mode: DictationModeID) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.mode = mode
    }
}

/// Where a session's mode came from. Raw values are diagnostics identifiers.
public enum ModeSource: String, Sendable {
    case `default`
    case appRule = "app-rule"
}

/// A mode chosen for one activation.
public struct ResolvedMode: Equatable, Sendable {
    public let mode: DictationMode
    public let source: ModeSource

    public init(mode: DictationMode, source: ModeSource) {
        self.mode = mode
        self.source = source
    }
}

/// Picks the mode at activation (E4-S7): the target app's rule, otherwise the
/// default; a mode that no longer exists falls back to the default, and a
/// missing default to Clean Writing. Pure.
public enum ModeResolver {
    public static func resolve(
        bundleIdentifier: String?, defaultMode: DictationModeID, library: PersonalizationLibrary
    ) -> ResolvedMode {
        let fallback = library.mode(defaultMode) ?? .clean
        guard let bundleIdentifier,
            let rule = library.appRules.first(where: {
                $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
            }),
            let mode = library.mode(rule.mode)
        else {
            return ResolvedMode(mode: fallback, source: .default)
        }
        return ResolvedMode(mode: mode, source: .appRule)
    }
}
