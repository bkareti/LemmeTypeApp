import Domain
import TestSupport
import Testing

/// E3-S4: the rewriting contract and runner guarantees.
struct TextRewritingTests {
    private let request = RewriteRequest(instruction: "shout", text: "hello", language: "en-US")

    @Test func fakeSatisfiesTheContract() async {
        #expect(await TextRewriterContract.verify(FakeTextRewriter()).isEmpty)
        #expect(await TextRewriterContract.verify(FakeTextRewriter(availability: .notEnabled)).isEmpty)
    }

    @Test func unavailableRewriterIsNeverCalled() async {
        for availability in [RewriterAvailability.notEnabled, .deviceNotEligible, .modelNotReady, .unavailable] {
            let rewriter = FakeTextRewriter(availability: availability)
            await #expect(throws: RewriteError.unavailable(availability)) {
                try await TextRewritingRunner().run(rewriter, request)
            }
            #expect(rewriter.rewriteCount == 0)
        }
    }

    @Test func cancellationNeverProducesAResult() async {
        let rewriter = FakeTextRewriter(delay: .seconds(5))
        let task = Task { try await TextRewritingRunner().run(rewriter, request) }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: RewriteError.cancelled) { try await task.value }
    }

    @Test func emptyOutputIsAnError() async {
        let rewriter = FakeTextRewriter(script: .text("  \n"))
        await #expect(throws: RewriteError.emptyResult) { try await TextRewritingRunner().run(rewriter, request) }
    }

    @Test func typedErrorsPassThrough() async {
        let rewriter = FakeTextRewriter(script: .failure(.refused))
        await #expect(throws: RewriteError.refused) { try await TextRewritingRunner().run(rewriter, request) }
    }

    @Test func identifiersAreStableAndSafe() {
        let errors: [RewriteError] = [
            .unavailable(.notEnabled), .tooLong, .refused, .emptyResult, .busy, .cancelled, .failed,
        ]
        #expect(errors.map(\.identifier).allSatisfy(DiagnosticValue.isSafeIdentifier))
        #expect(RewriteError.unavailable(.deviceNotEligible).identifier == "rewrite.device-not-eligible")
    }

    @Test func requestDescriptionIsRedacted() {
        #expect(!"\(request)".contains("hello"))
    }

    @Test func outputCleanupRemovesWrappersTheInputDidNotHave() {
        #expect(RewriteOutput.clean("  \"Short.\"  ", original: "A long sentence.") == "Short.")
        #expect(RewriteOutput.clean("“Short.”", original: "A long sentence.") == "Short.")
        #expect(RewriteOutput.clean("```\nlet x = 1\n```", original: "let x  = 1") == "let x = 1")
        #expect(RewriteOutput.clean("\"Quoted.\"", original: "\"Quoted original.\"") == "\"Quoted.\"")
        #expect(RewriteOutput.clean("- one\n- two", original: "one, two") == "- one\n- two")
    }
}
