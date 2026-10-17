import Domain
import Foundation
import TestSupport
import Testing

/// E3-S3: dictation fits into the surrounding text, deterministically.
struct ContextFormatterTests {
    /// `|` marks the caret in `around`.
    private func context(_ around: String) throws -> CursorContext {
        let parts = around.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let preceding = String(parts[0])
        return try #require(
            CursorContext(
                precedingText: preceding, followingText: parts.count > 1 ? String(parts[1]) : "",
                selection: TextSelection(location: preceding.utf16.count, length: 0)))
    }

    /// Clean Writing first, then the formatter, as the pipeline does.
    private func clean(_ spoken: String, in around: String) throws -> ContextFormatting {
        let written = TextCleaner().apply(spoken, mode: .clean).text
        return ContextFormatter.apply(written, mode: .clean, context: try context(around))
    }

    @Test func addsASpaceAfterAWord() throws {
        let result = ContextFormatter.apply("the update", mode: .exact, context: try context("Thanks for|"))
        #expect(result.text == " the update")
        #expect(result.transformations.map(\.rule) == [.leadingSpace])
    }

    @Test func continuesASentenceInLowercase() throws {
        let result = try clean("Then we left.", in: "We met on Monday and|")
        #expect(result.text == " then we left.")
        #expect(result.transformations.map(\.rule) == [.continuationCase, .leadingSpace])
    }

    @Test(arguments: ["Paris is lovely.", "I think so.", "NASA called.", "iPhone works.", "Monday works."])
    func namesAndIKeepTheirCase(spoken: String) throws {
        let result = try clean(spoken, in: "We met on Monday and|")
        #expect(result.text.dropFirst().first == TextCleaner().apply(spoken, mode: .clean).text.first)
        #expect(!result.transformations.contains { $0.rule == .continuationCase })
    }

    @Test func dropsThePeriodBeforeTheRestOfTheSentence() throws {
        let result = try clean("hello", in: "Say |world")
        #expect(result.text == "hello ")
        #expect(result.transformations.map(\.rule) == [.midSentencePeriod, .continuationCase, .trailingSpace])
    }

    @Test(arguments: ["|", "Done.|", "Really?|", "Wow!|", "Dear Sam,\n|", "She said “Stop.”|"])
    func keepsSentenceCapitalizationAtASentenceStart(around: String) throws {
        let result = try clean("then we left", in: around)
        #expect(result.text.trimmingCharacters(in: .whitespaces) == "Then we left.")
    }

    @Test func keepsThePeriodBeforeANewSentence() throws {
        let result = try clean("thanks", in: "|Hello there")
        #expect(result.text == "Thanks. ")
    }

    @Test func doesNotRepeatPunctuationNextToTheCaret() throws {
        let result = try clean("we can talk soon", in: "Okay|.")
        #expect(result.text == " we can talk soon")
        #expect(result.transformations.first?.rule == .duplicatePunctuation)
    }

    @Test func noSpaceAfterOpeningBracketOrInsideQuotes() throws {
        #expect(ContextFormatter.apply("note", mode: .exact, context: try context("(|)")).text == "note")
        #expect(ContextFormatter.apply("hi", mode: .exact, context: try context("He said \"|")).text == "hi")
        #expect(ContextFormatter.apply("next", mode: .exact, context: try context("one \"two\"|")).text == " next")
    }

    @Test func exactOnlyAdjustsSpacing() throws {
        let result = ContextFormatter.apply("Then we left.", mode: .exact, context: try context("and|world"))
        #expect(result.text == " Then we left. ")
        #expect(Set(result.transformations.map(\.rule)) == [.leadingSpace, .trailingSpace])
    }

    @Test func everyChangeNamesItsRule() throws {
        let result = try clean("Then we met.", in: "So|later")
        #expect(result.transformations.count == 4)
        #expect(
            Set(result.transformations.map(\.rule)) == [
                .midSentencePeriod, .continuationCase, .leadingSpace, .trailingSpace,
            ])
        #expect(result.text == " then we met ")
    }

    @Test func isDeterministic() throws {
        let first = try clean("Then we left.", in: "We met and|")
        for _ in 0..<5 { #expect(try clean("Then we left.", in: "We met and|") == first) }
    }

    @Test func pipelineWithoutContextOutputIsUnchanged() async throws {
        let engine = FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "then we left"))
        let delivery = FakeTextDelivery()
        let session = try TranscriptionPipelineTests.makeSession(mode: .clean)
        _ = await TranscriptionPipeline(engines: [engine], delivery: delivery).process(session) { _ in }
        #expect(delivery.delivered == ["Then we left."])
    }

    @Test func pipelineFormatsWithCapturedContext() async throws {
        let engine = FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "then we left"))
        let delivery = FakeTextDelivery()
        var session = try TranscriptionPipelineTests.makeSession(mode: .clean)
        let target = try #require(session.target).with(
            context: .captured(try context("We met and|"), purpose: .formatting))
        session = DictationSession(
            audio: session.audio, target: target, mode: .clean, language: "en-US")
        _ = await TranscriptionPipeline(engines: [engine], delivery: delivery).process(session) { _ in }
        #expect(delivery.delivered == [" then we left."])
    }
}
