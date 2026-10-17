import Domain
import Foundation
import TestSupport
import Testing

/// E4-S5 and E4-S7: modes, app rules, and how a session's mode is chosen.
struct DictationModeTests {
    @Test func builtInsHaveStableIdentifiersAndMatchEpicTwoModes() {
        #expect(DictationMode.builtIns.map(\.id.rawValue) == ["exact", "clean", "message"])
        #expect(DictationMode.builtIn(for: .exact) == .exact)
        #expect(DictationMode.builtIn(for: .clean) == .clean)
        #expect(DictationMode.message.finalPunctuation == .omit)
        #expect(DictationModeID.newCustom().rawValue.hasPrefix("custom-"))
        #expect(DictationModeID.newCustom().diagnosticIdentifier == "custom")
        #expect(DictationModeID.message.diagnosticIdentifier == "message")
    }

    @Test func customModesAreValidated() throws {
        var library = PersonalizationLibrary.empty
        #expect(throws: PersonalizationError.empty(.modeName)) { try library.upsert(DictationMode(name: "  ")) }
        #expect(throws: PersonalizationError.tooLong(.modeName, limit: 40)) {
            try library.upsert(DictationMode(name: String(repeating: "m", count: 41)))
        }
        // Built-in names are taken, ignoring case; built-ins can't be replaced.
        #expect(throws: PersonalizationError.duplicate(.modeName)) {
            try library.upsert(DictationMode(name: "clean writing"))
        }
        #expect(throws: PersonalizationError.duplicate(.modeName)) {
            try library.upsert(DictationMode(id: .clean, name: "Mine"))
        }
        try library.upsert(
            DictationMode(name: " Chat  ", language: " ", cleanupRules: [.capitalization, .fillerWords, .fillerWords]))
        let saved = try #require(library.modes.first)
        #expect(saved.name == "Chat")
        #expect(saved.language == nil)
        #expect(saved.cleanupRules == [.fillerWords, .capitalization])
        #expect(throws: PersonalizationError.duplicate(.modeName)) { try library.upsert(DictationMode(name: "CHAT")) }

        for index in 1..<PersonalizationLimits.customModes {
            try library.upsert(DictationMode(name: "Mode \(index)"))
        }
        #expect(throws: PersonalizationError.limitReached(.mode, limit: 20)) {
            try library.upsert(DictationMode(name: "One too many"))
        }
    }

    @Test func appRulesNeedAnExistingModeAndOneRulePerApp() throws {
        var library = PersonalizationLibrary.empty
        let chat = DictationMode(name: "Chat")
        try library.upsert(chat)
        #expect(throws: PersonalizationError.notFound) {
            try library.upsert(AppModeRule(bundleIdentifier: "com.tinyspeck.slackmacgap", mode: .newCustom()))
        }
        #expect(throws: PersonalizationError.empty(.application)) {
            try library.upsert(AppModeRule(bundleIdentifier: " ", mode: .clean))
        }
        try library.upsert(AppModeRule(bundleIdentifier: "com.tinyspeck.slackmacgap", mode: chat.id))
        try library.upsert(AppModeRule(bundleIdentifier: "com.apple.mail", mode: .clean))
        #expect(throws: PersonalizationError.duplicate(.application)) {
            try library.upsert(AppModeRule(bundleIdentifier: "COM.APPLE.MAIL", mode: .exact))
        }
        #expect(library.appRules(using: chat.id).map(\.bundleIdentifier) == ["com.tinyspeck.slackmacgap"])

        library.removeMode(chat.id)
        #expect(library.modes.isEmpty)
        #expect(library.appRules.map(\.bundleIdentifier) == ["com.apple.mail"])
    }

    @Test func resolverPrefersTheAppRuleThenTheDefault() throws {
        var library = PersonalizationLibrary.empty
        let chat = DictationMode(name: "Chat", finalPunctuation: .omit)
        try library.upsert(chat)
        try library.upsert(AppModeRule(bundleIdentifier: "com.tinyspeck.slackmacgap", mode: chat.id))

        let slack = ModeResolver.resolve(
            bundleIdentifier: "com.tinyspeck.slackmacgap", defaultMode: .exact, library: library)
        #expect(slack == ResolvedMode(mode: chat, source: .appRule))
        let mail = ModeResolver.resolve(bundleIdentifier: "com.apple.mail", defaultMode: .exact, library: library)
        #expect(mail == ResolvedMode(mode: .exact, source: .default))
        let noTarget = ModeResolver.resolve(bundleIdentifier: nil, defaultMode: .message, library: library)
        #expect(noTarget == ResolvedMode(mode: .message, source: .default))
        // A default that no longer exists falls back to Clean Writing.
        let missing = ModeResolver.resolve(bundleIdentifier: nil, defaultMode: .newCustom(), library: library)
        #expect(missing == ResolvedMode(mode: .clean, source: .default))
    }

    @Test func modesAndRulesRoundTripThroughTheArchive() throws {
        let chat = DictationMode(
            name: "Chat", engine: .whisper, language: "en-GB", writingMode: .clean, cleanupRules: [.capitalization],
            usesPersonalization: false, usesSnippets: false, finalPunctuation: .omit, output: .copy, appendsSpace: true)
        let library = try PersonalizationLibrary(
            vocabulary: [], replacements: [], snippets: [], modes: [chat],
            appRules: [AppModeRule(bundleIdentifier: "com.tinyspeck.slackmacgap", mode: chat.id)])
        #expect(try PersonalizationArchive.decode(try PersonalizationArchive(library).encoded()) == library)
        // Files written before modes existed still decode.
        let old = Data(#"{"format":"com.lemmetype.personalization","formatVersion":1,"vocabulary":[]}"#.utf8)
        #expect(try PersonalizationArchive.decode(old) == .empty)
    }

    @Test func duplicateGetsANewIdentity() {
        let copy = DictationMode.message.duplicated(named: "Message Copy")
        #expect(copy.id != DictationMode.message.id)
        #expect(!copy.isBuiltIn)
        #expect(copy.finalPunctuation == .omit)
        #expect(copy.name == "Message Copy")
    }
}

/// E4-S5: every mode setting is honoured by the pipeline.
struct ModePipelineTests {
    private struct Result {
        let delivered: [String]
        let copied: [String]
        let outcome: DictationOutcome
    }

    private func deliver(
        _ spoken: String, mode: DictationMode, source: ModeSource = .default,
        library: PersonalizationLibrary = .empty, followingText: String? = nil,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) async throws -> Result {
        let engine = FakeRecognitionEngine(id: .appleSpeech, script: .init(text: spoken))
        let delivery = FakeTextDelivery()
        let base = try TranscriptionPipelineTests.makeSession(mode: mode.writingMode)
        var target = try #require(base.target)
        if let followingText {
            let context = try #require(
                CursorContext(
                    precedingText: "", followingText: followingText, selection: TextSelection(location: 0, length: 0)))
            target = target.with(context: .captured(context, purpose: .formatting))
        }
        let session = DictationSession(
            audio: base.audio, target: target, mode: mode.writingMode, dictationMode: mode, modeSource: source,
            language: "en-US", personalization: library)
        let pipeline = TranscriptionPipeline(
            engines: [engine], delivery: delivery, copier: delivery, diagnostics: diagnostics)
        let outcome = await pipeline.process(session) { _ in }
        return Result(delivered: delivery.delivered, copied: delivery.copied, outcome: outcome)
    }

    private static func library() throws -> PersonalizationLibrary {
        try PersonalizationLibrary(
            vocabulary: [], replacements: [Replacement(spoken: "my email", written: "pat@example.com")],
            snippets: [Snippet(trigger: "sign off", expansion: "Best,\nPat")])
    }

    @Test func builtInModesMatchEpicTwoOutput() async throws {
        #expect(try await deliver("um hello   world", mode: .exact).delivered == ["um hello world"])
        #expect(try await deliver("um hello world", mode: .clean).delivered == ["Hello world."])
        #expect(try await deliver("um hello world", mode: .message).delivered == ["Hello world"])
        #expect(try await deliver("is it done", mode: .message).delivered == ["Is it done"])
    }

    @Test func messageKeepsQuestionMarksAndEllipses() {
        #expect(TranscriptionPipeline.omittingFinalPeriod("Done?") == "Done?")
        #expect(TranscriptionPipeline.omittingFinalPeriod("Wait...") == "Wait...")
        #expect(TranscriptionPipeline.omittingFinalPeriod("Done.") == "Done")
    }

    @Test func switchedOffCleanupRulesDoNotRun() async throws {
        let mode = DictationMode(name: "Keep fillers", cleanupRules: [.capitalization, .terminalPunctuation])
        #expect(try await deliver("um hello world", mode: mode).delivered == ["Um hello world."])
    }

    @Test func personalizationAndSnippetsCanBeSwitchedOff() async throws {
        let library = try Self.library()
        let enabled = DictationMode(name: "On")
        #expect(
            try await deliver("send to my email", mode: enabled, library: library).delivered == [
                "Send to pat@example.com."
            ])
        #expect(try await deliver("sign off", mode: enabled, library: library).delivered == ["Best,\nPat"])

        let off = DictationMode(name: "Off", usesPersonalization: false, usesSnippets: false)
        #expect(try await deliver("send to my email", mode: off, library: library).delivered == ["Send to my email."])
        #expect(try await deliver("sign off", mode: off, library: library).delivered == ["Sign off."])
    }

    @Test func copyOnlyNeverTouchesTheTarget() async throws {
        let result = try await deliver("hello", mode: DictationMode(name: "Copy", output: .copy))
        #expect(result.delivered.isEmpty)
        #expect(result.copied == ["Hello."])
        #expect(result.outcome == .delivered(.copied))
    }

    @Test func trailingSpaceIsAddedOnce() async throws {
        let spaced = DictationMode(name: "Spaced", appendsSpace: true)
        #expect(try await deliver("hello", mode: spaced).delivered == ["Hello. "])
        // Not when the text after the cursor already starts with a space.
        let beforeSpace = try await deliver("hello", mode: spaced, followingText: " world").delivered
        #expect(beforeSpace.count == 1 && beforeSpace.first?.hasSuffix(" ") == false)
    }

    @Test func diagnosticsNameTheModeWithoutItsName() async throws {
        let diagnostics = RecordingDiagnostics()
        _ = try await deliver(
            "hello", mode: DictationMode(name: "Secret Mode Name"), source: .appRule, diagnostics: diagnostics)
        let event = try #require(diagnostics.events.first { $0.name == "session.delivered" })
        #expect(event.attributes["dictationMode"] == .identifier("custom"))
        #expect(event.attributes["modeSource"] == .identifier("app-rule"))
        #expect(!String(describing: diagnostics.events).contains("Secret"))
    }
}
