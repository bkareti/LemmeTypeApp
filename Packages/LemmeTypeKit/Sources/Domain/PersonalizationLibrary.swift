import Foundation

/// Size limits for personalization (E4-S1). They keep the store small and
/// matching fast; lengths are in characters.
public enum PersonalizationLimits {
    public static let termLength = 100
    public static let soundsLikePerTerm = 5
    public static let spokenLength = 100
    public static let writtenLength = 1_000
    public static let triggerLength = 60
    public static let expansionLength = 4_000
    public static let vocabularyEntries = 500
    public static let replacements = 500
    public static let snippets = 200
    public static let customModes = 20
    public static let appRules = 100
    public static let bundleIdentifierLength = 255
    public static let languageLength = 35
    /// Vocabulary terms passed to an engine as recognition hints.
    public static let recognitionHints = 100
}

/// The user's vocabulary, replacements, snippets, custom modes, and per-app
/// mode rules (E4-S1, E4-S5, E4-S7). A value type:
/// sessions capture a copy when recording starts, so edits apply from the next
/// dictation. Every mutation normalizes and validates; a library that exists
/// is always valid.
public struct PersonalizationLibrary: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public private(set) var vocabulary: [VocabularyEntry]
    public private(set) var replacements: [Replacement]
    public private(set) var snippets: [Snippet]
    /// Custom modes only; built-ins are ``DictationMode/builtIns``.
    public private(set) var modes: [DictationMode]
    public private(set) var appRules: [AppModeRule]

    public static let empty = PersonalizationLibrary()

    public init() {
        vocabulary = []
        replacements = []
        snippets = []
        modes = []
        appRules = []
    }

    /// A library from stored or imported items; fails on the first invalid one.
    public init(
        vocabulary: [VocabularyEntry], replacements: [Replacement], snippets: [Snippet],
        modes: [DictationMode] = [], appRules: [AppModeRule] = []
    ) throws(PersonalizationError) {
        self.init()
        for entry in vocabulary { try upsert(entry) }
        for replacement in replacements { try upsert(replacement) }
        for snippet in snippets { try upsert(snippet) }
        for mode in modes { try upsert(mode) }
        for rule in appRules { try upsert(rule) }
    }

    public var isEmpty: Bool {
        vocabulary.isEmpty && replacements.isEmpty && snippets.isEmpty && modes.isEmpty && appRules.isEmpty
    }

    public var description: String {
        "PersonalizationLibrary(vocabulary: \(vocabulary.count), replacements: \(replacements.count), "
            + "snippets: \(snippets.count), modes: \(modes.count), appRules: \(appRules.count))"
    }

    /// Built-in modes first, then custom modes in the user's order.
    public var allModes: [DictationMode] { DictationMode.builtIns + modes }

    /// A built-in or custom mode by identifier.
    public func mode(_ id: DictationModeID) -> DictationMode? {
        allModes.first { $0.id == id }
    }

    public var debugDescription: String { description }

    /// Terms an engine should expect, in the user's order.
    public var recognitionHints: [String] {
        Array(vocabulary.prefix(PersonalizationLimits.recognitionHints).map(\.term))
    }

    // MARK: Vocabulary

    /// Adds `entry`, or replaces the entry with the same id.
    public mutating func upsert(_ entry: VocabularyEntry) throws(PersonalizationError) {
        var entry = entry
        entry.term = PersonalizationText.normalizedPhrase(entry.term)
        try Self.check(entry.term, .term, limit: PersonalizationLimits.termLength)
        let termKey = PersonalizationText.key(entry.term)
        var spellings: [String] = []
        for spelling in entry.soundsLike.map(PersonalizationText.normalizedPhrase) where !spelling.isEmpty {
            let key = PersonalizationText.key(spelling)
            guard key != termKey, !spellings.contains(where: { PersonalizationText.key($0) == key }) else { continue }
            try Self.check(spelling, .soundsLike, limit: PersonalizationLimits.termLength)
            spellings.append(spelling)
        }
        guard spellings.count <= PersonalizationLimits.soundsLikePerTerm else {
            throw .tooManySpellings(limit: PersonalizationLimits.soundsLikePerTerm)
        }
        entry.soundsLike = spellings
        if vocabulary.contains(where: { $0.id != entry.id && PersonalizationText.key($0.term) == termKey }) {
            throw .duplicate(.term)
        }
        try Self.insert(entry, into: &vocabulary, kind: .vocabulary, limit: PersonalizationLimits.vocabularyEntries)
    }

    public mutating func removeVocabulary(_ id: VocabularyEntry.ID) {
        vocabulary.removeAll { $0.id == id }
    }

    // MARK: Replacements

    public mutating func upsert(_ replacement: Replacement) throws(PersonalizationError) {
        var replacement = replacement
        replacement.spoken = PersonalizationText.normalizedPhrase(replacement.spoken)
        replacement.written = replacement.written.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.check(replacement.spoken, .spoken, limit: PersonalizationLimits.spokenLength)
        try Self.check(replacement.written, .written, limit: PersonalizationLimits.writtenLength)
        let key = PersonalizationText.key(replacement.spoken)
        if replacements.contains(where: { $0.id != replacement.id && PersonalizationText.key($0.spoken) == key }) {
            throw .duplicate(.spoken)
        }
        try Self.insert(replacement, into: &replacements, kind: .replacement, limit: PersonalizationLimits.replacements)
    }

    public mutating func removeReplacement(_ id: Replacement.ID) {
        replacements.removeAll { $0.id == id }
    }

    // MARK: Snippets

    public mutating func upsert(_ snippet: Snippet) throws(PersonalizationError) {
        var snippet = snippet
        snippet.trigger = PersonalizationText.normalizedPhrase(snippet.trigger)
        try Self.check(snippet.trigger, .trigger, limit: PersonalizationLimits.triggerLength)
        guard snippet.expansion.contains(where: { !$0.isWhitespace }) else { throw .empty(.expansion) }
        guard snippet.expansion.count <= PersonalizationLimits.expansionLength else {
            throw .tooLong(.expansion, limit: PersonalizationLimits.expansionLength)
        }
        let key = SnippetMatcher.key(snippet.trigger)
        guard !key.isEmpty else { throw .empty(.trigger) }
        if snippets.contains(where: { $0.id != snippet.id && SnippetMatcher.key($0.trigger) == key }) {
            throw .duplicate(.trigger)
        }
        try Self.insert(snippet, into: &snippets, kind: .snippet, limit: PersonalizationLimits.snippets)
    }

    public mutating func removeSnippet(_ id: Snippet.ID) {
        snippets.removeAll { $0.id == id }
    }

    // MARK: Modes

    /// Adds or updates a custom mode. Built-in modes can't be changed.
    public mutating func upsert(_ mode: DictationMode) throws(PersonalizationError) {
        guard !mode.isBuiltIn else { throw .duplicate(.modeName) }
        var mode = mode
        mode.name = PersonalizationText.normalizedPhrase(mode.name)
        try Self.check(mode.name, .modeName, limit: DictationMode.maximumNameLength)
        let key = PersonalizationText.key(mode.name)
        if allModes.contains(where: { $0.id != mode.id && PersonalizationText.key($0.name) == key }) {
            throw .duplicate(.modeName)
        }
        if let language = mode.language {
            let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count <= PersonalizationLimits.languageLength else {
                throw .tooLong(.language, limit: PersonalizationLimits.languageLength)
            }
            mode.language = trimmed.isEmpty ? nil : trimmed
        }
        let enabled = Set(mode.cleanupRules)
        mode.cleanupRules = CleanupRule.allCases.filter(enabled.contains)
        try Self.insert(mode, into: &modes, kind: .mode, limit: PersonalizationLimits.customModes)
    }

    /// Removes a custom mode and every app rule that used it.
    public mutating func removeMode(_ id: DictationModeID) {
        modes.removeAll { $0.id == id }
        appRules.removeAll { $0.mode == id }
    }

    /// App rules that use `mode`, for the delete confirmation.
    public func appRules(using mode: DictationModeID) -> [AppModeRule] {
        appRules.filter { $0.mode == mode }
    }

    // MARK: App rules

    /// Adds or updates a rule; one rule per app, and the mode must exist.
    public mutating func upsert(_ rule: AppModeRule) throws(PersonalizationError) {
        var rule = rule
        rule.bundleIdentifier = rule.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.check(rule.bundleIdentifier, .application, limit: PersonalizationLimits.bundleIdentifierLength)
        guard mode(rule.mode) != nil else { throw .notFound }
        if appRules.contains(where: {
            $0.id != rule.id && $0.bundleIdentifier.caseInsensitiveCompare(rule.bundleIdentifier) == .orderedSame
        }) {
            throw .duplicate(.application)
        }
        try Self.insert(rule, into: &appRules, kind: .appRule, limit: PersonalizationLimits.appRules)
    }

    public mutating func removeAppRule(_ id: AppModeRule.ID) {
        appRules.removeAll { $0.id == id }
    }

    // MARK: Helpers

    private static func check(_ value: String, _ field: PersonalizationField, limit: Int) throws(PersonalizationError) {
        guard !value.isEmpty else { throw .empty(field) }
        guard value.count <= limit else { throw .tooLong(field, limit: limit) }
    }

    private static func insert<Item: Identifiable>(
        _ item: Item, into items: inout [Item], kind: PersonalizationKind, limit: Int
    ) throws(PersonalizationError) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            return
        }
        guard items.count < limit else { throw .limitReached(kind, limit: limit) }
        items.append(item)
    }
}
