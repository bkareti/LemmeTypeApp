import Domain
import TestSupport
import Testing

@testable import Delivery

/// Accessibility insertion into the captured field (E2-S7).
struct AccessibilityInsertionTests {
    private func deliver(
        _ text: String, driver: FakeAccessibilityDriver, target: ActivationTarget?,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) async -> DeliveryOutcome {
        // Fallback off: these tests cover Accessibility outcomes alone.
        let pasteboard = FakePasteboard()
        return await DictationTextDelivery(
            driver: driver, pasteboard: pasteboard,
            keystroke: FakePasteKeystroke(pasteboard: pasteboard, driver: driver),
            policy: { ClipboardFallbackPolicy(fallback: .off) }, diagnostics: diagnostics, sleep: { _ in }
        ).deliver(text, to: target)
    }

    @Test func insertsOnceAtTheCaretOfTheCapturedField() async {
        let field = FakeTextElement(text: "Dear Ana, ")
        let driver = FakeAccessibilityDriver(focused: field)

        let outcome = await deliver("thanks.", driver: driver, target: FakeAccessibilityDriver.target(for: field))

        #expect(outcome == .delivered(.accessibility))
        #expect(field.writes == ["thanks."])
        #expect(field.text == "Dear Ana, thanks.")
    }

    @Test func replacesTheSelectionThatExistedAtActivation() async {
        let field = FakeTextElement(text: "Meet on Tuesday.", selection: TextSelection(location: 8, length: 7))
        let driver = FakeAccessibilityDriver(focused: field)

        let outcome = await deliver("Friday", driver: driver, target: FakeAccessibilityDriver.target(for: field))

        #expect(outcome == .delivered(.accessibility))
        #expect(field.text == "Meet on Friday.")
    }

    @Test func sameLengthReplacementCountsAsInserted() async {
        let field = FakeTextElement(text: "abc", selection: TextSelection(location: 0, length: 3))
        let driver = FakeAccessibilityDriver(focused: field)
        #expect(
            await deliver("xyz", driver: driver, target: FakeAccessibilityDriver.target(for: field))
                == .delivered(.accessibility))
        #expect(field.text == "xyz")
    }

    @Test func aDifferentFocusedFieldNeverReceivesText() async {
        let original = FakeTextElement(text: "")
        let other = FakeTextElement(text: "")
        let driver = FakeAccessibilityDriver(focused: original)
        let target = FakeAccessibilityDriver.target(for: original)
        driver.focus(other)  // the user clicked elsewhere while processing

        #expect(await deliver("hello", driver: driver, target: target) == .problem(.targetChanged))
        #expect(other.writes.isEmpty && original.writes.isEmpty)

        driver.focus(original)  // Retry Insert after returning to the field
        #expect(await deliver("hello", driver: driver, target: target) == .delivered(.accessibility))
        #expect(original.text == "hello")
    }

    @Test func anotherAppInFrontIsATargetChange() async {
        let original = FakeTextElement(processIdentifier: 1)
        let driver = FakeAccessibilityDriver(focused: original)
        let target = FakeAccessibilityDriver.target(for: original)
        driver.focus(FakeTextElement(processIdentifier: 2))
        #expect(await deliver("hello", driver: driver, target: target) == .problem(.targetChanged))
    }

    @Test func passwordFieldsAreNeverWrittenOrRead() async {
        var behavior = FakeTextElement.Behavior()
        behavior.isSecure = true
        let field = FakeTextElement(behavior: behavior)
        let driver = FakeAccessibilityDriver(focused: field)

        #expect(
            await deliver("hunter2", driver: driver, target: FakeAccessibilityDriver.target(for: field))
                == .problem(.secureField))
        #expect(field.writes.isEmpty)
        #expect(!driver.readSecureField)
    }

    @Test func secureKeyboardEntryBlocksInsertion() async {
        let field = FakeTextElement()
        let driver = FakeAccessibilityDriver(focused: field)
        driver.setSecureInput(true)
        #expect(
            await deliver("x", driver: driver, target: FakeAccessibilityDriver.target(for: field))
                == .problem(.secureField))
        #expect(field.writes.isEmpty)
    }

    @Test func missingTrustAndMissingTargetAreTyped() async {
        let field = FakeTextElement()
        let driver = FakeAccessibilityDriver(trusted: false, focused: field)
        #expect(
            await deliver("x", driver: driver, target: FakeAccessibilityDriver.target(for: field))
                == .problem(.permissionMissing))
        #expect(await deliver("x", driver: FakeAccessibilityDriver(), target: nil) == .problem(.noTarget))
        #expect(field.writes.isEmpty)
    }

    @Test func readOnlyFieldsAreUnsupported() async {
        var behavior = FakeTextElement.Behavior()
        behavior.acceptsSelectedText = false
        let field = FakeTextElement(behavior: behavior)
        let driver = FakeAccessibilityDriver(focused: field)
        #expect(
            await deliver("x", driver: driver, target: FakeAccessibilityDriver.target(for: field))
                == .problem(.unsupported))
        #expect(field.writes.isEmpty)
    }

    @Test func targetCapturedWithoutAnElementIsUnsupportedForAccessibility() async {
        let driver = FakeAccessibilityDriver(focused: FakeTextElement(processIdentifier: 4242))
        let target = FakeAccessibilityDriver.target(for: nil, processIdentifier: 4242)
        #expect(await deliver("x", driver: driver, target: target) == .problem(.unsupported))
    }

    @Test func appsThatIgnoreWritesAreDetectedWithoutDuplicates() async {
        var behavior = FakeTextElement.Behavior()
        behavior.appliesWrites = false  // reports success, changes nothing
        let field = FakeTextElement(text: "abc", behavior: behavior)
        let driver = FakeAccessibilityDriver(focused: field)

        #expect(
            await deliver("x", driver: driver, target: FakeAccessibilityDriver.target(for: field))
                == .problem(.unsupported))
        #expect(field.writes == ["x"])  // one attempt, never retried
    }

    @Test func aRefusedWriteThatChangedNothingIsAFailure() async {
        var behavior = FakeTextElement.Behavior()
        behavior.appliesWrites = false
        behavior.reportsSuccess = false
        let field = FakeTextElement(behavior: behavior)
        let driver = FakeAccessibilityDriver(focused: field)
        let inserter = AccessibilityTextInserter(driver: driver, sleep: { _ in })
        #expect(await inserter.insert("x", into: field) == .notInserted(.failed))
    }

    @Test func anErrorThatStillChangedTheFieldCountsAsInserted() async {
        var behavior = FakeTextElement.Behavior()
        behavior.reportsSuccess = false
        let field = FakeTextElement(behavior: behavior)
        let inserter = AccessibilityTextInserter(driver: FakeAccessibilityDriver(focused: field), sleep: { _ in })
        #expect(await inserter.insert("x", into: field) == .inserted)
        #expect(field.writes.count == 1)
    }

    @Test func unverifiableErrorsAreUncertainSoNothingIsRetried() async {
        var behavior = FakeTextElement.Behavior()
        behavior.reportsSuccess = false
        behavior.exposesCount = false
        let field = FakeTextElement(behavior: behavior)
        let driver = FakeAccessibilityDriver(focused: field)
        let inserter = AccessibilityTextInserter(driver: driver, sleep: { _ in })
        #expect(await inserter.insert("x", into: field) == .uncertain)
        #expect(
            await deliver("x", driver: driver, target: FakeAccessibilityDriver.target(for: field)) == .problem(.failed))
    }

    @Test func slowAppsGetTimeToApplyTheChange() async {
        var behavior = FakeTextElement.Behavior()
        behavior.readsBeforeChangeIsVisible = 1
        let field = FakeTextElement(behavior: behavior)
        let inserter = AccessibilityTextInserter(driver: FakeAccessibilityDriver(focused: field), sleep: { _ in })
        #expect(await inserter.insert("x", into: field) == .inserted)
    }

    @Test func diagnosticsCarryOutcomesButNeverText() async {
        let diagnostics = RecordingDiagnostics()
        let field = FakeTextElement()
        let driver = FakeAccessibilityDriver(focused: field)
        _ = await deliver(
            "canary-dictated", driver: driver, target: FakeAccessibilityDriver.target(for: field),
            diagnostics: diagnostics)
        _ = await deliver("canary-dictated", driver: driver, target: nil, diagnostics: diagnostics)

        #expect(diagnostics.events.map(\.name) == ["delivery.delivered", "delivery.problem"])
        #expect(diagnostics.events[1].attributes["problem"] == .identifier("no-target"))
        #expect(!String(describing: diagnostics.events).contains("canary"))
    }
}
