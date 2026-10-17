import Domain
import Foundation
import Testing

/// E4-S1: the personalization library validates every change.
struct PersonalizationLibraryTests {
    @Test func normalizesAndStoresValidEntries() throws {
        var library = PersonalizationLibrary.empty
        try library.upsert(
            VocabularyEntry(term: "  Lemme\tType ", soundsLike: ["lemme type", " ", "LEMME TYPE", "lemme"]))
        try library.upsert(Replacement(spoken: " my  email ", written: " pat@example.com\n"))
        try library.upsert(Snippet(trigger: "Sign off", expansion: "Best regards,\nPat\n"))

        #expect(library.vocabulary.first?.term == "Lemme Type")
        // Blank, duplicate, and same-as-term spellings are dropped.
        #expect(library.vocabulary.first?.soundsLike == ["lemme"])
        #expect(library.replacements.first?.spoken == "my email")
        #expect(library.replacements.first?.written == "pat@example.com")
        // Expansions are kept exactly, line breaks included.
        #expect(library.snippets.first?.expansion == "Best regards,\nPat\n")
    }

    @Test func rejectsEmptyValues() {
        var library = PersonalizationLibrary.empty
        #expect(throws: PersonalizationError.empty(.term)) { try library.upsert(VocabularyEntry(term: "  ")) }
        #expect(throws: PersonalizationError.empty(.spoken)) {
            try library.upsert(Replacement(spoken: "", written: "x"))
        }
        #expect(throws: PersonalizationError.empty(.written)) {
            try library.upsert(Replacement(spoken: "x", written: " \n"))
        }
        #expect(throws: PersonalizationError.empty(.trigger)) {
            try library.upsert(Snippet(trigger: "…", expansion: "x"))
        }
        #expect(throws: PersonalizationError.empty(.expansion)) {
            try library.upsert(Snippet(trigger: "x", expansion: "\n\n"))
        }
    }

    @Test func enforcesLengthLimits() {
        var library = PersonalizationLibrary.empty
        let long = { (count: Int) in String(repeating: "a", count: count) }
        #expect(throws: PersonalizationError.tooLong(.term, limit: 100)) {
            try library.upsert(VocabularyEntry(term: long(101)))
        }
        #expect(throws: PersonalizationError.tooLong(.soundsLike, limit: 100)) {
            try library.upsert(VocabularyEntry(term: "a", soundsLike: [long(101)]))
        }
        #expect(throws: PersonalizationError.tooManySpellings(limit: 5)) {
            try library.upsert(VocabularyEntry(term: "a", soundsLike: ["b", "c", "d", "e", "f", "g"]))
        }
        #expect(throws: PersonalizationError.tooLong(.spoken, limit: 100)) {
            try library.upsert(Replacement(spoken: long(101), written: "x"))
        }
        #expect(throws: PersonalizationError.tooLong(.written, limit: 1_000)) {
            try library.upsert(Replacement(spoken: "x", written: long(1_001)))
        }
        #expect(throws: PersonalizationError.tooLong(.trigger, limit: 60)) {
            try library.upsert(Snippet(trigger: long(61), expansion: "x"))
        }
        #expect(throws: PersonalizationError.tooLong(.expansion, limit: 4_000)) {
            try library.upsert(Snippet(trigger: "x", expansion: long(4_001)))
        }
        #expect(throws: Never.self) { try library.upsert(Snippet(trigger: long(60), expansion: long(4_000))) }
    }

    @Test func rejectsDuplicatesIgnoringCase() throws {
        var library = PersonalizationLibrary.empty
        try library.upsert(VocabularyEntry(term: "LemmeType"))
        try library.upsert(Replacement(spoken: "my email", written: "a"))
        try library.upsert(Snippet(trigger: "sign off", expansion: "b"))

        #expect(throws: PersonalizationError.duplicate(.term)) {
            try library.upsert(VocabularyEntry(term: "lemmetype"))
        }
        #expect(throws: PersonalizationError.duplicate(.spoken)) {
            try library.upsert(Replacement(spoken: "My  Email", written: "c"))
        }
        #expect(throws: PersonalizationError.duplicate(.trigger)) {
            try library.upsert(Snippet(trigger: "Sign off.", expansion: "d"))
        }
    }

    @Test func updatingAnEntryKeepsItsPlaceAndAllowsItsOwnKey() throws {
        var library = PersonalizationLibrary.empty
        let first = VocabularyEntry(term: "Alpha")
        try library.upsert(first)
        try library.upsert(VocabularyEntry(term: "Beta"))
        var edited = first
        edited.term = "ALPHA"
        try library.upsert(edited)
        #expect(library.vocabulary.map(\.term) == ["ALPHA", "Beta"])
        library.removeVocabulary(first.id)
        #expect(library.vocabulary.map(\.term) == ["Beta"])
    }

    @Test func enforcesCountLimits() throws {
        var library = PersonalizationLibrary.empty
        for index in 0..<PersonalizationLimits.snippets {
            try library.upsert(Snippet(trigger: "snippet \(index)", expansion: "x"))
        }
        #expect(throws: PersonalizationError.limitReached(.snippet, limit: 200)) {
            try library.upsert(Snippet(trigger: "one more", expansion: "x"))
        }
        // Editing an existing item is still allowed at the limit.
        var existing = try #require(library.snippets.first)
        existing.expansion = "y"
        try library.upsert(existing)
        #expect(library.snippets.first?.expansion == "y")
    }

    @Test func errorIdentifiersAreStableAndLowercase() {
        let errors: [PersonalizationError] =
            PersonalizationField.allCases.flatMap { [.empty($0), .tooLong($0, limit: 1), .duplicate($0)] }
            + PersonalizationKind.allCases.map { .limitReached($0, limit: 1) }
            + [.tooManySpellings(limit: 5), .notFound, .unreadable, .unsupportedVersion, .invalidFile, .storageFailure]
        for error in errors {
            #expect(DiagnosticValue.isSafeIdentifier(error.identifier), "\(error.identifier)")
            #expect(error.identifier.hasPrefix("personalization."))
        }
        #expect(PersonalizationError.duplicate(.trigger).identifier == "personalization.duplicate-trigger")
        #expect(PersonalizationError.unreadable.identifier == "personalization.unreadable")
    }

    @Test func descriptionsAreRedacted() throws {
        var library = PersonalizationLibrary.empty
        try library.upsert(VocabularyEntry(term: "CANARY-TERM", soundsLike: ["canary sound"]))
        try library.upsert(Replacement(spoken: "canary spoken", written: "CANARY-WRITTEN"))
        try library.upsert(Snippet(trigger: "canary trigger", expansion: "CANARY-EXPANSION"))
        let printed = [
            "\(library)", String(reflecting: library), "\(library.vocabulary)", "\(library.replacements)",
            "\(library.snippets)", String(reflecting: library.snippets[0]),
        ].joined()
        #expect(!printed.lowercased().contains("canary"))
        #expect("\(library)".contains("vocabulary: 1"))
    }

    @Test func recognitionHintsAreTheFirstHundredTerms() throws {
        var library = PersonalizationLibrary.empty
        #expect(library.recognitionHints.isEmpty)
        for index in 0..<120 {
            try library.upsert(VocabularyEntry(term: "Term\(index)", soundsLike: ["term number \(index)"]))
        }
        #expect(library.recognitionHints.count == 100)
        #expect(library.recognitionHints.first == "Term0")
    }

    @Test func archiveRoundTripsAndRejectsUnknownFiles() throws {
        var library = PersonalizationLibrary.empty
        try library.upsert(VocabularyEntry(term: "LemmeType", soundsLike: ["lemme type"]))
        try library.upsert(Replacement(spoken: "my email", written: "pat@example.com"))
        try library.upsert(Snippet(trigger: "sign off", expansion: "Best,\nPat"))

        let data = try PersonalizationArchive(library).encoded()
        #expect(try PersonalizationArchive.decode(data) == library)
        #expect((String(bytes: data, encoding: .utf8) ?? "").contains("\"formatVersion\" : 1"))

        #expect(throws: PersonalizationError.invalidFile) { try PersonalizationArchive.decode(Data("[]".utf8)) }
        #expect(throws: PersonalizationError.invalidFile) {
            try PersonalizationArchive.decode(Data(#"{"format":"other","formatVersion":1}"#.utf8))
        }
        #expect(throws: PersonalizationError.unsupportedVersion) {
            try PersonalizationArchive.decode(
                Data(#"{"format":"com.lemmetype.personalization","formatVersion":2}"#.utf8))
        }
        // An invalid item fails the whole file.
        let invalid = #"""
            {"format":"com.lemmetype.personalization","formatVersion":1,
             "snippets":[{"id":"\#(UUID().uuidString)","trigger":"","expansion":"x"}]}
            """#
        #expect(throws: PersonalizationError.empty(.trigger)) { try PersonalizationArchive.decode(Data(invalid.utf8)) }
    }
}
