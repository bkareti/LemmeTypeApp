import Domain
import Foundation
import Testing

/// E4-S8: export, import (merge or replace), and what counts as a duplicate.
struct PersonalizationArchiveTests {
    static func sample() throws -> PersonalizationLibrary {
        let chat = DictationMode(name: "Chat", finalPunctuation: .omit, appendsSpace: true)
        return try PersonalizationLibrary(
            vocabulary: [VocabularyEntry(term: "LemmeType", soundsLike: ["lemme type"])],
            replacements: [Replacement(spoken: "my email", written: "pat@example.com")],
            snippets: [Snippet(trigger: "sign off", expansion: "Best,\nPat")],
            modes: [chat],
            appRules: [
                AppModeRule(bundleIdentifier: "com.tinyspeck.slackmacgap", mode: chat.id),
                AppModeRule(bundleIdentifier: "com.apple.mail", mode: .clean),
            ])
    }

    @Test func exportThenImportIntoAnEmptyLibraryReproducesIt() throws {
        let library = try Self.sample()
        let data = try PersonalizationArchive(library).encoded()
        #expect(try PersonalizationArchive.decode(data) == library)
        #expect(PersonalizationSummary(library).total == 6)
        // Readable, versioned JSON.
        let text = String(bytes: data, encoding: .utf8) ?? ""
        #expect(text.contains(#""format" : "com.lemmetype.personalization""#))
        #expect(text.contains("\n"))
    }

    @Test func mergeAddsNewItemsAndSkipsDuplicates() throws {
        var current = PersonalizationLibrary.empty
        try current.upsert(Replacement(spoken: "My Email", written: "other@example.com"))
        try current.upsert(DictationMode(name: "chat"))

        let merge = current.merging(try Self.sample())
        // Added: word, snippet, Mail rule. Skipped: replacement, Chat mode, and
        // the Slack rule that pointed at the skipped mode.
        #expect(merge.added == 3)
        #expect(merge.skipped == 3)
        #expect(merge.library.replacements.map(\.written) == ["other@example.com"])
        #expect(merge.library.appRules.map(\.bundleIdentifier) == ["com.apple.mail"])

        // Merging the same file again adds nothing.
        let again = merge.library.merging(try Self.sample())
        #expect(again.added == 0)
        #expect(again.library == merge.library)
    }

    @Test func mergedModesKeepTheirRules() throws {
        let merge = PersonalizationLibrary.empty.merging(try Self.sample())
        #expect(merge.skipped == 0)
        let chat = try #require(merge.library.modes.first)
        #expect(chat.finalPunctuation == .omit)
        #expect(merge.library.appRules(using: chat.id).map(\.bundleIdentifier) == ["com.tinyspeck.slackmacgap"])
    }
}
