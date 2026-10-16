import Domain
import Foundation
import Testing

/// Before/after corpus for Exact Dictation and Clean Writing. Each case names
/// the rules expected to change the text, so every transformation is traced
/// to the rule that made it.
struct TextCleanerTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let category: String
        let input: String
        let clean: String
        let rules: Set<CleanupRule>

        init(_ category: String, _ input: String, _ clean: String, _ rules: Set<CleanupRule>) {
            self.category = category
            self.input = input
            self.clean = clean
            self.rules = rules
        }

        var testDescription: String { "\(category): \(input)" }
    }

    static let corpus: [Case] = [
        // Normal speech
        Case("normal", "thanks for the update", "Thanks for the update.", [.capitalization, .terminalPunctuation]),
        Case("normal", "Thanks for the update.", "Thanks for the update.", []),
        Case(
            "normal", "um can you send me the slides", "Can you send me the slides.",
            [.fillerWords, .capitalization, .terminalPunctuation]),
        Case("normal", "i think i'm free tomorrow.", "I think I'm free tomorrow.", [.capitalization]),
        Case("normal", "I saw the the movie.", "I saw the movie.", [.repeatedWords]),
        Case("normal", "She said that that was fine.", "She said that that was fine.", []),
        Case("normal", "He had had enough.", "He had had enough.", []),
        Case("normal", "great. see you then.", "Great. See you then.", [.capitalization]),
        Case("normal", "Uh, I guess so.", "I guess so.", [.fillerWords]),
        Case("normal", "Sounds good, um.", "Sounds good.", [.fillerWords]),
        // Spoken punctuation
        Case(
            "spoken", "hello comma how are you question mark", "Hello, how are you?",
            [.spokenPunctuation, .capitalization]),
        Case(
            "spoken", "first point new line second point", "First point\nSecond point.",
            [.spokenPunctuation, .capitalization, .terminalPunctuation]),
        Case("spoken", "that's all period", "That's all.", [.spokenPunctuation, .capitalization]),
        Case("spoken", "The period of time was short.", "The period of time was short.", []),
        Case("spoken", "Wow exclamation mark", "Wow!", [.spokenPunctuation]),
        // Self-corrections
        Case(
            "correction", "Let's meet on Tuesday—sorry—Wednesday at noon.", "Let's meet on Wednesday at noon.",
            [.selfCorrection]),
        Case(
            "correction", "Let's meet on Tuesday, sorry, Wednesday.", "Let's meet on Wednesday.", [.selfCorrection]),
        Case("correction", "Book it for June no wait July.", "Book it for July.", [.selfCorrection]),
        Case("correction", "Order 5 sorry 6 boxes.", "Order 6 boxes.", [.selfCorrection]),
        Case("correction", "Sorry I'm late.", "Sorry I'm late.", []),
        Case("correction", "Call Tuesday, sorry about that.", "Call Tuesday, sorry about that.", []),
        Case("correction", "I mean it.", "I mean it.", []),
        Case("correction", "Tell Anna sorry Ben is out.", "Tell Anna sorry Ben is out.", []),
        // Technical
        Case(
            "technical", "rename getUserName to fetchUserName", "Rename getUserName to fetchUserName.",
            [.capitalization, .terminalPunctuation]),
        Case("technical", "set max_retries to three.", "Set max_retries to three.", [.capitalization]),
        Case(
            "technical", "open config/app.yaml please", "Open config/app.yaml please.",
            [.capitalization, .terminalPunctuation]),
        Case("technical", "run `make test` now.", "Run `make test` now.", [.capitalization]),
        Case("technical", "increment retry_count", "Increment retry_count.", [.capitalization, .terminalPunctuation]),
        Case("technical", "edit main.swift", "Edit main.swift", [.capitalization]),
        // Numbers
        Case("numeric", "the total is $420.50", "The total is $420.50", [.capitalization]),
        Case("numeric", "We grew 18% in Q2.", "We grew 18% in Q2.", []),
        Case("numeric", "call 555-123-4567", "Call 555-123-4567", [.capitalization]),
        Case("numeric", "the the 2 2 options.", "The 2 2 options.", [.repeatedWords, .capitalization]),
        // URLs and email
        Case("url", "visit example.com", "Visit example.com", [.capitalization]),
        Case("url", "https://lemmetype.app/docs is the link.", "https://lemmetype.app/docs is the link.", []),
        Case("email", "email me at ana@example.com", "Email me at ana@example.com", [.capitalization]),
        Case("email", "ana@example.com wrote back.", "ana@example.com wrote back.", []),
        // Quotes and code
        Case(
            "quote", "she wrote \"um the the plan\" yesterday.", "She wrote \"um the the plan\" yesterday.",
            [.capitalization]),
        Case("code", "if x == nil return", "If x == nil return.", [.capitalization, .terminalPunctuation]),
    ]

    @Test(arguments: corpus)
    func cleanWritingMatchesTheCorpus(_ testCase: Case) {
        let result = TextCleaner().apply(testCase.input, mode: .clean)
        #expect(result.text == testCase.clean)
        #expect(Set(result.transformations.map(\.rule)) == testCase.rules)
    }

    @Test(arguments: corpus)
    func exactDictationNeverChangesWords(_ testCase: Case) {
        let result = TextCleaner().apply("  " + testCase.input + "   ", mode: .exact)
        #expect(result.text == testCase.input)
        #expect(result.transformations.isEmpty)
    }

    @Test(arguments: corpus)
    func cleanWritingIsDeterministic(_ testCase: Case) {
        let first = TextCleaner().apply(testCase.input, mode: .clean)
        let second = TextCleaner().apply(testCase.input, mode: .clean)
        #expect(first == second)
    }

    @Test func protectedTokensSurviveCleanWriting() {
        let protected = [
            "420.50", "18%", "https://lemmetype.app/docs", "ana@example.com", "getUserName", "max_retries",
        ]
        let input = "um " + protected.joined(separator: " um ")
        let output = TextCleaner().apply(input, mode: .clean).text
        for token in protected {
            #expect(output.contains(token), "\(token) changed in \(output)")
        }
    }

    @Test func eachRuleCanBeTurnedOff() {
        let input = "um hello comma the the world"
        for rule in CleanupRule.allCases {
            var rules = Set(CleanupRule.allCases)
            rules.remove(rule)
            let result = TextCleaner(configuration: CleanupConfiguration(enabledRules: rules))
                .apply(input, mode: .clean)
            #expect(!result.transformations.contains { $0.rule == rule })
        }
        let none = TextCleaner(configuration: CleanupConfiguration(enabledRules: [])).apply(input, mode: .clean)
        #expect(none.text == input)
    }

    @Test func exactKeepsLineBreaksAndCollapsesBlankRuns() {
        #expect(TextCleaner.normalizeWhitespace("a  b\n\n\n\nc\t d \n") == "a b\n\nc d")
    }

    @Test func transformationsRecordBeforeAndAfter() {
        let result = TextCleaner().apply("Meet Tuesday—sorry—Wednesday.", mode: .clean)
        #expect(
            result.transformations == [
                CleanupTransformation(
                    rule: .selfCorrection, before: "Tuesday — sorry — Wednesday.", after: "Wednesday.")
            ])
    }

    @Test func configurationRoundTripsForSettings() throws {
        let configuration = CleanupConfiguration(enabledRules: [.capitalization, .fillerWords])
        let data = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(CleanupConfiguration.self, from: data) == configuration)
    }
}
