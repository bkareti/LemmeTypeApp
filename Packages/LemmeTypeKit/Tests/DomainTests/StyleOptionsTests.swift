import Domain
import Foundation
import Testing

/// E10-S1 and E10-S2: the final choices, the "no rewrite" combination, the
/// fixed instruction wording, Exact bypass, and migration of saved modes.
struct StyleOptionsTests {
    @Test func theChoicesAreTheDocumentedOnes() {
        #expect(Tone.allCases.map(\.rawValue) == ["neutral", "professional", "friendly", "casual"])
        #expect(WritingFormat.allCases.map(\.rawValue) == ["plain-text", "message", "email", "bullet-list"])
        #expect(LengthPreference.allCases.map(\.rawValue) == ["original", "concise"])
    }

    @Test func neutralPlainOriginalMeansNoRewrite() {
        #expect(StyleOptions.none.isNone)
        #expect(StyleOptions().isNone)
        #expect(StyleInstruction.make(.none) == nil)
        #expect(StyleOptions.none.identifier == "none")
        // Any single change makes it a rewrite.
        #expect(!StyleOptions(tone: .casual).isNone)
        #expect(!StyleOptions(format: .message).isNone)
        #expect(!StyleOptions(length: .concise).isNone)
    }

    @Test func tonesFormatsAndLengthsAreIndependent() {
        for tone in Tone.allCases {
            for format in WritingFormat.allCases {
                for length in LengthPreference.allCases {
                    let options = StyleOptions(tone: tone, format: format, length: length)
                    #expect(options.tone == tone && options.format == format && options.length == length)
                }
            }
        }
    }

    @Test func everyCombinationHasDeterministicDocumentedWording() throws {
        var seen = Set<String>()
        for tone in Tone.allCases {
            for format in WritingFormat.allCases {
                for length in LengthPreference.allCases {
                    let options = StyleOptions(tone: tone, format: format, length: length)
                    guard !options.isNone else { continue }
                    let first = try #require(StyleInstruction.make(options))
                    #expect(first == StyleInstruction.make(options), "wording must be deterministic")
                    #expect(first.hasPrefix("Rewrite the passage"))
                    #expect(first.contains("name, number, date, negation"))
                    #expect(first.contains("Do not add facts, names, recipients, numbers, dates, or links"))
                    seen.insert(first)
                }
            }
        }
        #expect(seen.count == 31, "every non-empty combination has its own instruction")
    }

    @Test func eachChoiceContributesItsOwnWords() throws {
        func text(_ options: StyleOptions) throws -> String { try #require(StyleInstruction.make(options)) }
        #expect(try text(StyleOptions(tone: .professional)).contains("professional, polite tone"))
        #expect(try text(StyleOptions(tone: .friendly)).contains("warm, friendly tone"))
        #expect(try text(StyleOptions(tone: .casual)).contains("relaxed, casual tone"))
        #expect(try text(StyleOptions(format: .message)).contains("short chat message"))
        #expect(try text(StyleOptions(format: .email)).contains("never add a recipient or sender name"))
        #expect(try text(StyleOptions(format: .bulletList)).contains("each line starting with \"- \""))
        #expect(try text(StyleOptions(length: .concise)).contains("Make it shorter"))
        #expect(try !text(StyleOptions(tone: .casual)).contains("Make it shorter"))
    }

    // MARK: Exact bypass and migration (E10-S2)

    @Test func exactDictationNeverRewritesEvenWithAStyleSet() {
        let style = StyleOptions(tone: .professional, format: .email, length: .concise)
        let exact = DictationMode(name: "Exact email", writingMode: .exact, style: style)
        #expect(exact.style == style, "the choice is stored")
        #expect(exact.effectiveStyle == .none, "but never applied")
        let clean = DictationMode(name: "Clean email", writingMode: .clean, style: style)
        #expect(clean.effectiveStyle == style)
    }

    @Test func builtInModesHaveNoStyle() {
        // Proper English (E12-S3) corrects grammar on purpose.
        for mode in DictationMode.builtIns where mode.id != .properEnglish {
            #expect(mode.style == .none)
            #expect(mode.effectiveStyle == .none)
        }
    }

    @Test func modesSavedBeforeStyleDecodeWithNoStyle() throws {
        // The stored form written by the previous version (no `style` key).
        let stored = """
            {"id":"custom-0a1b","name":"Chat","language":"en-GB","writingMode":"clean",
             "cleanupRules":["filler-words"],"usesPersonalization":true,"usesSnippets":false,
             "finalPunctuation":"omit","output":"copy","appendsSpace":true}
            """
        let mode = try JSONDecoder().decode(DictationMode.self, from: Data(stored.utf8))
        #expect(mode.style == .none)
        #expect(mode.effectiveStyle == .none)
        #expect(mode.finalPunctuation == .omit && mode.output == .copy && mode.appendsSpace)
    }

    @Test func aPartialStyleKeepsDefaultsForTheMissingChoices() throws {
        let style = try JSONDecoder().decode(StyleOptions.self, from: Data(#"{"tone":"friendly"}"#.utf8))
        #expect(style == StyleOptions(tone: .friendly))
    }

    @Test func styleSurvivesEncodingDuplicateAndArchive() throws {
        let style = StyleOptions(tone: .professional, format: .email, length: .concise)
        let mode = DictationMode(name: "Client email", style: style)
        #expect(try JSONDecoder().decode(DictationMode.self, from: JSONEncoder().encode(mode)) == mode)
        #expect(mode.duplicated(named: "Copy").style == style)

        let library = try PersonalizationLibrary(vocabulary: [], replacements: [], snippets: [], modes: [mode])
        let data = try PersonalizationArchive(library).encoded()
        #expect(try PersonalizationArchive.decode(data).modes.first?.style == style)
    }

    @Test func anArchiveWrittenBeforeStyleStillImports() throws {
        let library = try PersonalizationLibrary(
            vocabulary: [], replacements: [], snippets: [],
            modes: [DictationMode(name: "Chat", finalPunctuation: .omit)])
        var json = try #require(String(bytes: try PersonalizationArchive(library).encoded(), encoding: .utf8))
        // Simulate the previous version's file: no style key anywhere.
        json = json.replacingOccurrences(
            of: #"(?s),?\s*"style"\s*:\s*\{[^}]*\}"#, with: "", options: .regularExpression)
        #expect(!json.contains("\"style\""))
        let imported = try PersonalizationArchive.decode(Data(json.utf8))
        #expect(imported.modes.first?.name == "Chat")
        #expect(imported.modes.first?.style == StyleOptions.none)
    }

    @Test func diagnosticIdentifiersAreSafeLowercaseNames() {
        let options = StyleOptions(tone: .professional, format: .bulletList, length: .concise)
        #expect(options.identifier == "professional-bullet-list-concise")
        #expect(DiagnosticValue.isSafeIdentifier(options.identifier))
    }
}
