/// Counts of a personalization file's contents, for the import confirmation
/// (E4-S8). Numbers only.
public struct PersonalizationSummary: Equatable, Sendable {
    public let vocabulary: Int
    public let replacements: Int
    public let snippets: Int
    public let modes: Int
    public let appRules: Int

    public init(_ library: PersonalizationLibrary) {
        vocabulary = library.vocabulary.count
        replacements = library.replacements.count
        snippets = library.snippets.count
        modes = library.modes.count
        appRules = library.appRules.count
    }

    public var total: Int { vocabulary + replacements + snippets + modes + appRules }
}

/// The result of merging an imported library into the current one.
public struct PersonalizationMerge: Equatable, Sendable {
    public let library: PersonalizationLibrary
    public let added: Int
    /// Duplicates (same term, phrase, trigger, mode name, or app) and items
    /// over a limit.
    public let skipped: Int
}

extension PersonalizationLibrary {
    /// Adds every item of `other` that doesn't clash with this library (E4-S8).
    /// Imported items get new identities, so merging the same file twice adds
    /// nothing the second time; app rules follow their imported modes.
    public func merging(_ other: PersonalizationLibrary) -> PersonalizationMerge {
        var merged = self
        var added = 0
        var skipped = 0
        func attempt(_ change: (inout PersonalizationLibrary) throws(PersonalizationError) -> Void) {
            do {
                try change(&merged)
                added += 1
            } catch {
                skipped += 1
            }
        }
        for entry in other.vocabulary {
            attempt { library throws(PersonalizationError) in
                try library.upsert(VocabularyEntry(term: entry.term, soundsLike: entry.soundsLike))
            }
        }
        for replacement in other.replacements {
            attempt { library throws(PersonalizationError) in
                try library.upsert(Replacement(spoken: replacement.spoken, written: replacement.written))
            }
        }
        for snippet in other.snippets {
            attempt { library throws(PersonalizationError) in
                try library.upsert(Snippet(trigger: snippet.trigger, expansion: snippet.expansion))
            }
        }
        var modeIDs: [DictationModeID: DictationModeID] = [:]
        for mode in other.modes {
            let copy = mode.duplicated(named: mode.name)
            attempt { library throws(PersonalizationError) in
                try library.upsert(copy)
                modeIDs[mode.id] = copy.id
            }
        }
        for rule in other.appRules {
            // A rule for an imported mode that was skipped is skipped too.
            let mode = rule.mode.isBuiltIn ? rule.mode : modeIDs[rule.mode]
            guard let mode else {
                skipped += 1
                continue
            }
            attempt { library throws(PersonalizationError) in
                try library.upsert(AppModeRule(bundleIdentifier: rule.bundleIdentifier, mode: mode))
            }
        }
        return PersonalizationMerge(library: merged, added: added, skipped: skipped)
    }
}
