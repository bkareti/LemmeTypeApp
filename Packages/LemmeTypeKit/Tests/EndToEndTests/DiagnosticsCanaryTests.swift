import Domain
import Foundation
import Support
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E6-S6: unique canary text goes into every place sensitive text can enter —
/// speech, the field, the selection, the app name, the rewriter output, the
/// vocabulary, and the history — across every session type and the failure
/// paths. None of it may appear in the diagnostics, an encoded report, an error
/// identifier, or the history's metadata.
@MainActor
@Suite(.serialized)
struct DiagnosticsCanaryTests {
    static let spoken = "CANARY-SPOKEN-a1f3"
    static let field = "CANARY-FIELD-b2e4"
    static let selection = "CANARY-SELECTION-c3d5"
    static let rewritten = "CANARY-REWRITE-d4c6"
    static let app = "CANARY-APP-e5b7"
    static let history = "CANARY-HISTORY-f6a8"

    static let all = [spoken, field, selection, rewritten, app, history]

    static func report(_ events: [DiagnosticEvent]) throws -> String {
        let report = DiagnosticsReport(
            generatedAt: Date(), appVersion: "1.0", appBuild: "1", osVersion: "macOS", hardwareModel: "Mac",
            permissions: [:], activationMode: "push-to-talk", events: events)
        return String(data: try DiagnosticsReportEncoder.encode(report), encoding: .utf8) ?? ""
    }

    static func expectClean(_ text: String, _ scenario: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for canary in all {
            #expect(!text.contains(canary), "\(canary) leaked in \(scenario)", sourceLocation: sourceLocation)
        }
    }

    static func expectSafeNames(_ events: [DiagnosticEvent], sourceLocation: SourceLocation = #_sourceLocation) {
        for event in events {
            #expect(
                DiagnosticValue.isSafeIdentifier(event.name), "event name \(event.name)", sourceLocation: sourceLocation
            )
            for (key, value) in event.attributes {
                #expect(DiagnosticValue.isSafeIdentifier(key) || key.allSatisfy { $0.isLetter || $0.isNumber })
                if case .identifier(let raw) = value {
                    #expect(
                        DiagnosticValue.isSafeIdentifier(raw), "value \(raw) of \(key)", sourceLocation: sourceLocation)
                }
            }
        }
    }

    // MARK: Sessions

    // macOS only: built on the Mac's shortcut and cursor-context harness.
    #if os(macOS)
        @Test func contextFormattingAndVoiceEditingLeaveNoCanary() async throws {
            let sentence = FakeTextElement(
                text: "\(Self.field) ", selection: TextSelection(location: Self.field.utf16.count + 1, length: 0))
            let formatting = ContextEndToEndTests.Harness(
                field: sentence, spoken: Self.spoken, bundleIdentifier: "com.example.canary-app-e5b7")
            defer { formatting.cleanUp() }
            await formatting.press(.defaultDictation)
            #expect(sentence.text.contains(Self.spoken.lowercased()) || sentence.text.contains(Self.spoken))
            let formattingEvents = formatting.diagnostics.snapshot()
            Self.expectClean(formatting.report, "context formatting")
            Self.expectClean(try Self.report(formattingEvents), "context formatting report")
            Self.expectSafeNames(formattingEvents)

            let selected = FakeTextElement(
                text: "Please \(Self.selection) today.",
                selection: TextSelection(location: 7, length: Self.selection.utf16.count))
            let editing = ContextEndToEndTests.Harness(
                field: selected, spoken: Self.spoken, rewriter: FakeTextRewriter(script: .text(Self.rewritten)))
            defer { editing.cleanUp() }
            await editing.press(.defaultVoiceEdit)
            #expect(selected.text.contains(Self.rewritten), "the edit ran, so the canary was in play")
            let editingEvents = editing.diagnostics.snapshot()
            Self.expectClean(editing.report, "voice editing")
            Self.expectClean(try Self.report(editingEvents), "voice editing report")
            Self.expectSafeNames(editingEvents)
        }
    #endif

    @Test func rewriteTranslationAndHistoryLeaveNoCanary() async throws {
        let preferences = FakePreferences()
        preferences.historyRetention = .oneWeek
        let store = FakeDictationHistoryStore()
        let service = DictationHistoryService(store: store, preferences: preferences)

        let draft = FakeTextElement()
        let styled = try StyleRewritingEndToEndTests.Harness(
            field: draft, spoken: Self.spoken, style: StyleRewritingEndToEndTests.email,
            rewriter: FakeTextRewriter(script: .text("Hi,\n\n\(Self.spoken)\n\nThanks,")), history: service)
        defer { styled.cleanUp() }
        await styled.dictate(into: draft)
        styled.coordinator.perform(.insertText)
        await styled.coordinator.settle()
        #expect(draft.text.contains(Self.spoken), "the rewrite was inserted")
        #expect(
            store.history.entries.map(\.text).contains { $0.contains(Self.spoken) }, "history has the accepted text")
        let events = styled.diagnostics.events
        Self.expectClean(styled.diagnosticsText, "rewrite and history")
        Self.expectClean(try Self.report(events), "rewrite report")
        Self.expectSafeNames(events)

        // The history holds the accepted text only — no other canary.
        let archive = String(data: try DictationHistoryArchive(store.history).encoded(), encoding: .utf8) ?? ""
        for canary in [Self.field, Self.selection, Self.rewritten, Self.app, Self.history] {
            #expect(!archive.contains(canary), "\(canary) in the history file")
        }

        let translated = FakeTextElement()
        let translation = try StyleRewritingEndToEndTests.Harness(
            field: translated, spoken: Self.spoken, style: .none, writing: .exact, rewriter: FakeTextRewriter(),
            language: "hi", output: .english, history: service)
        defer { translation.cleanUp() }
        await translation.dictate(into: translated)
        translation.coordinator.perform(.insertText)
        await translation.coordinator.settle()
        Self.expectClean(translation.diagnosticsText, "translation")
        Self.expectClean(try Self.report(translation.diagnostics.events), "translation report")
    }

    // MARK: Failure paths

    // macOS only: built on the Mac's shortcut and cursor-context harness.
    #if os(macOS)
        @Test func failuresReportIdentifiersNotText() async throws {
            let refusedField = FakeTextElement(
                text: "Keep \(Self.selection).",
                selection: TextSelection(location: 5, length: Self.selection.utf16.count))
            let refusal = ContextEndToEndTests.Harness(
                field: refusedField, spoken: Self.spoken, rewriter: FakeTextRewriter(script: .failure(.refused)))
            defer { refusal.cleanUp() }
            await refusal.press(.defaultVoiceEdit)
            #expect(refusal.coordinator.state == .needsAttention(.rewriteFailed(.refused)))
            Self.expectClean(refusal.report, "rewriter refusal")
            Self.expectClean(try Self.report(refusal.diagnostics.snapshot()), "refusal report")

            let moving = FakeTextElement(
                text: "Alpha \(Self.field) gamma", selection: TextSelection(location: 6, length: Self.field.utf16.count)
            )
            let changed = ContextEndToEndTests.Harness(field: moving, spoken: Self.spoken)
            defer { changed.cleanUp() }
            await changed.press(.defaultVoiceEdit) { moving.select(TextSelection(location: 0, length: 5)) }
            Self.expectClean(changed.report, "changed selection")
            Self.expectClean(try Self.report(changed.diagnostics.snapshot()), "changed selection report")
        }
    #endif

    @Test func errorIdentifiersAreSafe() {
        let identifiers = [
            DictationHistoryError.unreadable.identifier, DictationHistoryError.unsupportedVersion.identifier,
            DictationHistoryError.storageFailure.identifier,
            DictationIssue.rewriteFailed(.refused).identifier, DictationIssue.reviewTranslation.identifier,
            DictationIssue.noEngineAvailable.identifier,
        ]
        for identifier in identifiers {
            #expect(DiagnosticValue.isSafeIdentifier(identifier), "\(identifier)")
        }
    }
}
