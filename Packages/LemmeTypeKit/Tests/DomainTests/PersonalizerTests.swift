import Domain
import Testing

/// E4-S2: vocabulary and replacements, whole words, longest match, one pass.
struct PersonalizerTests {
    private func library(
        vocabulary: [VocabularyEntry] = [], replacements: [Replacement] = []
    ) throws -> PersonalizationLibrary {
        try PersonalizationLibrary(vocabulary: vocabulary, replacements: replacements, snippets: [])
    }

    @Test func vocabularySpellingBecomesTheTerm() throws {
        let personalizer = Personalizer(
            library: try library(vocabulary: [VocabularyEntry(term: "LemmeType", soundsLike: ["lemme type"])]))
        let result = personalizer.apply("I use lemme type daily")
        #expect(result.text == "I use LemmeType daily")
        #expect(result.transformations == [.init(rule: .vocabulary, before: "lemme type", after: "LemmeType")])
    }

    @Test func vocabularyFixesLetterCaseOfTheTermItself() throws {
        let personalizer = Personalizer(library: try library(vocabulary: [VocabularyEntry(term: "iPhone")]))
        #expect(personalizer.apply("My Iphone and IPHONE.").text == "My iPhone and iPhone.")
        // Already correct: no change is recorded.
        #expect(personalizer.apply("My iPhone").transformations.isEmpty)
    }

    @Test func replacementWritesTheWrittenText() throws {
        let personalizer = Personalizer(
            library: try library(replacements: [Replacement(spoken: "my email", written: "pat@example.com")]))
        #expect(personalizer.apply("Send it to my email.").text == "Send it to pat@example.com.")
        #expect(personalizer.apply("My Email, please").text == "pat@example.com, please")
    }

    @Test func matchesWholeWordsOnly() throws {
        let personalizer = Personalizer(
            library: try library(replacements: [Replacement(spoken: "my email", written: "pat@example.com")]))
        #expect(personalizer.apply("myemail").text == "myemail")
        #expect(personalizer.apply("my emails").text == "my emails")
        #expect(personalizer.apply("tommy email").text == "tommy email")
        #expect(personalizer.apply("my email's subject").text == "pat@example.com's subject")
    }

    @Test func longestPhraseWins() throws {
        let personalizer = Personalizer(
            library: try library(replacements: [
                Replacement(spoken: "new york", written: "NY"),
                Replacement(spoken: "new york city", written: "NYC"),
            ]))
        #expect(personalizer.apply("I love new york city and new york").text == "I love NYC and NY")
    }

    @Test func replacedTextIsNeverMatchedAgain() throws {
        let personalizer = Personalizer(
            library: try library(replacements: [
                Replacement(spoken: "alpha", written: "beta"),
                Replacement(spoken: "beta", written: "gamma"),
            ]))
        #expect(personalizer.apply("alpha beta").text == "beta gamma")
    }

    @Test func replacementBeatsAVocabularySpellingOfTheSameLength() throws {
        let personalizer = Personalizer(
            library: try library(
                vocabulary: [VocabularyEntry(term: "Docs", soundsLike: ["the docs"])],
                replacements: [Replacement(spoken: "the docs", written: "https://docs.example.com")]))
        let result = personalizer.apply("read the docs")
        #expect(result.text == "read https://docs.example.com")
        #expect(result.transformations.map(\.rule) == [.replacement])
    }

    @Test func emptyLibraryLeavesTextUntouched() {
        let personalizer = Personalizer(library: .empty)
        #expect(personalizer.isEmpty)
        let text = "Nothing  changes here.\nNot even spacing."
        #expect(personalizer.apply(text) == PersonalizationResult(text: text, transformations: []))
        #expect(Personalizer.apply(text, library: .empty) == text)
    }

    @Test func keepsLineBreaksAndPunctuationAroundMatches() throws {
        let personalizer = Personalizer(
            library: try library(vocabulary: [VocabularyEntry(term: "Kubernetes", soundsLike: ["cooper netties"])]))
        #expect(personalizer.apply("(cooper netties)\ncooper netties!").text == "(Kubernetes)\nKubernetes!")
    }
}

/// E4-S3: whole-utterance snippet triggers.
struct SnippetMatcherTests {
    private let snippets = [
        Snippet(trigger: "sign off", expansion: "Best regards,\nPat"),
        Snippet(trigger: "my address", expansion: "1 Infinite Loop"),
    ]

    @Test func matchesTheWholeUtteranceIgnoringCaseAndEdgePunctuation() {
        #expect(SnippetMatcher.match("Sign off.", in: snippets)?.expansion == "Best regards,\nPat")
        #expect(SnippetMatcher.match("  SIGN   OFF!  ", in: snippets)?.expansion == "Best regards,\nPat")
        #expect(SnippetMatcher.match("“my address”", in: snippets)?.expansion == "1 Infinite Loop")
    }

    @Test func neverMatchesInsideALongerSentence() {
        #expect(SnippetMatcher.match("Please sign off now.", in: snippets) == nil)
        #expect(SnippetMatcher.match("sign off sign off", in: snippets) == nil)
        #expect(SnippetMatcher.match("", in: snippets) == nil)
        #expect(SnippetMatcher.match("...", in: snippets) == nil)
    }
}
