import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E7-S8: the behaviour classes real apps fall into, each run through the whole
/// local loop (recorder → pipeline → delivery) against a fake field. A row in
/// `docs/testing/compatibility-matrix.md` names each test; real apps stay in the
/// manual matrix (MA-28, MA-29, MA-65).
@MainActor
@Suite(.serialized)
struct CompatibilityProfileTests {
    typealias Harness = DictationEndToEndTests.Harness
    static let clean = "Let's meet on Wednesday."

    private func field(_ configure: (inout FakeTextElement.Behavior) -> Void) -> FakeTextElement {
        var behavior = FakeTextElement.Behavior()
        configure(&behavior)
        return FakeTextElement(behavior: behavior)
    }

    private func dictate(_ field: FakeTextElement, clipboard: [[String: Data]]? = nil) async -> Harness {
        let harness =
            clipboard.map { Harness(field: field, clipboard: $0) }
            ?? Harness(field: field)
        await harness.dictate(into: FakeAccessibilityDriver.target(for: field))
        return harness
    }

    // P1 — a field that takes Accessibility writes (Notes, Mail, TextEdit, Messages)
    @Test func p1AccessibilityWritableField() async {
        let target = field { _ in }
        let harness = await dictate(target)
        defer { harness.cleanUp() }
        #expect(harness.coordinator.lastDelivery == .accessibility)
        #expect(target.text == Self.clean && target.writes.count == 1 && target.pastes.isEmpty)
    }

    // P2 — reports success but ignores the write (Electron, Word): paste and restore the clipboard
    @Test func p2FieldThatIgnoresAccessibilityWrites() async {
        let target = field { $0.appliesWrites = false }
        let previous: [[String: Data]] = [[FakePasteboard.plainText: Data("keep me".utf8)]]
        let harness = await dictate(target, clipboard: previous)
        defer { harness.cleanUp() }
        #expect(harness.coordinator.lastDelivery == .paste)
        #expect(target.text == Self.clean && target.pastes.count == 1)
        #expect(harness.pasteboard.items == previous, "the user's clipboard comes back")
    }

    // P3 — a field that refuses selected-text writes (some web views, custom editors)
    @Test func p3FieldThatRefusesSelectedTextWrites() async {
        let target = field { $0.acceptsSelectedText = false }
        let harness = await dictate(target)
        defer { harness.cleanUp() }
        #expect(harness.coordinator.lastDelivery == .paste)
        #expect(target.text == Self.clean && target.pastes.count == 1)
    }

    // P4 — the write call itself fails
    @Test func p4FieldWhoseWriteFails() async {
        let target = field {
            $0.reportsSuccess = false; $0.appliesWrites = false
        }
        let harness = await dictate(target)
        defer { harness.cleanUp() }
        #expect(harness.coordinator.lastDelivery == .paste)
        #expect(target.text == Self.clean)
    }

    // P5 — a field that never reports its length: an accepted write is trusted, the text is typed once
    @Test func p5FieldThatCannotBeCountedButAcceptsTheWrite() async {
        let target = field { $0.exposesCount = false }
        let harness = await dictate(target)
        defer { harness.cleanUp() }
        #expect(harness.coordinator.lastDelivery == .accessibility)
        #expect(target.text == Self.clean && target.writes.count == 1 && target.pastes.isEmpty)
    }

    // P5b — no length and a write that gives no answer: success is unknowable, so never guess and never duplicate
    @Test func p5bFieldThatCannotBeVerifiedGetsNoSecondAttempt() async {
        let target = field {
            $0.exposesCount = false
            $0.reportsSuccess = false
        }
        let harness = await dictate(target)
        defer { harness.cleanUp() }
        #expect(target.pastes.isEmpty, "no automatic second attempt that could type the text twice")
        #expect(harness.coordinator.state == .needsAttention(.deliveryFailed(.failed)))
        #expect(harness.coordinator.attentionActions.contains(.copyText), "the user can still get the text")
        harness.coordinator.perform(.copyText)
        await harness.coordinator.settle()
        #expect(harness.copier.copied == [Self.clean])
    }

    // P6 — a password or secure field
    @Test func p6SecureFieldNeverReceivesText() async {
        let target = field { $0.isSecure = true }
        let harness = await dictate(target)
        defer { harness.cleanUp() }
        #expect(harness.coordinator.state == .needsAttention(.deliveryFailed(.secureField)))
        #expect(target.writes.isEmpty && target.pastes.isEmpty)
    }

    // P7 — the user moves to another field while the text is processed
    @Test func p7FocusMovesAway() async {
        let first = field { _ in }
        let second = field { _ in }
        let harness = Harness(field: first, recognitionDelay: .milliseconds(30))
        defer { harness.cleanUp() }
        harness.coordinator.handle(.start(FakeAccessibilityDriver.target(for: first)))
        await harness.coordinator.settle()
        harness.source.emitTone(seconds: 0.4)
        harness.coordinator.handle(.stop)
        harness.driver.focus(second)
        await harness.coordinator.settle()
        #expect(harness.coordinator.state == .needsAttention(.deliveryFailed(.targetChanged)))
        #expect(second.writes.isEmpty && first.writes.isEmpty)
    }

    // P8 — Accessibility trust is missing or was revoked
    @Test func p8AccessibilityNotTrusted() async {
        let target = field { _ in }
        let harness = Harness(field: target)
        defer { harness.cleanUp() }
        harness.driver.setTrusted(false)
        await harness.dictate(into: FakeAccessibilityDriver.target(for: target))
        #expect(target.writes.isEmpty && target.pastes.isEmpty)
        guard case .needsAttention = harness.coordinator.state else {
            Issue.record("expected the recorder to ask for attention, got \(harness.coordinator.state)")
            return
        }
    }

    // P9 — no readable text range (Slack, VS Code): context formatting is skipped, insertion still works
    @Test func p9FieldWithoutReadableTextRanges() async {
        let target = FakeTextElement(
            text: "Hello ", selection: TextSelection(location: 6, length: 0),
            behavior: {
                var behavior = FakeTextElement.Behavior()
                behavior.exposesText = false
                return behavior
            }())
        let harness = ContextEndToEndTests.Harness(field: target, spoken: "this is a test")
        defer { harness.cleanUp() }
        await harness.press(.defaultDictation)
        #expect(target.text.hasPrefix("Hello "), "the field's own text is untouched")
        #expect(target.text.contains("this is a test") || target.text.contains("This is a test"))
        #expect(harness.report.contains("unreadable"), "the activation recorded that no context could be read")
    }

    // P10 — a password manager or an app the user excluded: nothing around the cursor is read
    @Test func p10SensitiveAndExcludedAppsAreNotRead() async {
        let sensitive = FakeTextElement(text: "secret ", selection: TextSelection(location: 7, length: 0))
        let first = ContextEndToEndTests.Harness(
            field: sensitive, spoken: "hello", bundleIdentifier: "com.1password.1password")
        defer { first.cleanUp() }
        await first.press(.defaultDictation)
        #expect(sensitive.textReads.isEmpty, "a password manager's text is never read")
        #expect(first.report.contains("sensitive-app"))

        let excluded = FakeTextElement(text: "private ", selection: TextSelection(location: 8, length: 0))
        let preferences = FakePreferences(
            usesFormattingContext: true, contextExcludedApplications: ["com.example.Private"])
        let second = ContextEndToEndTests.Harness(
            field: excluded, spoken: "hello", preferences: preferences, bundleIdentifier: "com.example.Private")
        defer { second.cleanUp() }
        await second.press(.defaultDictation)
        #expect(excluded.textReads.isEmpty, "an excluded app's text is never read")
        #expect(second.report.contains("excluded-app"))
    }
}
