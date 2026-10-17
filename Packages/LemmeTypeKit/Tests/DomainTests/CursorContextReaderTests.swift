import Domain
import Synchronization
import TestSupport
import Testing

/// E3-S2: what is read, and what is never read, when a shortcut is pressed.
struct CursorContextReaderTests {
    private let allowAll = ContextPolicy(usesFormattingContext: true, allowsVoiceEditing: true)

    private func reader(
        _ driver: FakeAccessibilityDriver, policy: ContextPolicy? = nil
    ) -> CursorContextReader<FakeAccessibilityDriver> {
        let policy = policy ?? allowAll
        return CursorContextReader(driver: driver, policy: { policy })
    }

    @Test func capturesBoundedWindowOnce() throws {
        let prefix = String(repeating: "x", count: 300)
        let element = FakeTextElement(text: prefix + "Thanks for world and more text after the caret here, padding")
        element.select(TextSelection(location: 310, length: 0))  // after "Thanks for"
        let driver = FakeAccessibilityDriver(focused: element)

        let capture = reader(driver).read(for: FakeAccessibilityDriver.target(for: element), purpose: .formatting)

        let context = try #require(capture.context)
        #expect(context.precedingText.utf16.count == CursorContext.maxPrecedingLength)
        #expect(context.precedingText.hasSuffix("Thanks for"))
        #expect(context.followingText.utf16.count == CursorContext.maxFollowingLength)
        #expect(context.followingText.hasPrefix(" world"))
        #expect(context.selectedText == nil)
        #expect(element.textReads.count == 2)  // one before, one after
    }

    @Test func caretAtStartReadsOnlyFollowingText() throws {
        let element = FakeTextElement(text: "world")
        element.select(TextSelection(location: 0, length: 0))
        let driver = FakeAccessibilityDriver(focused: element)

        let context = try #require(
            reader(driver).read(for: FakeAccessibilityDriver.target(for: element), purpose: .formatting).context)

        #expect(context.precedingText.isEmpty)
        #expect(context.followingText == "world")
        #expect(element.textReads == [TextSelection(location: 0, length: 5)])
    }

    @Test func editingCapturesTheSelection() throws {
        let element = FakeTextElement(text: "Hello brave new world")
        element.select(TextSelection(location: 6, length: 9))
        let driver = FakeAccessibilityDriver(focused: element)

        let context = try #require(
            reader(driver).read(for: FakeAccessibilityDriver.target(for: element), purpose: .editing).context)

        #expect(context.selectedText == "brave new")
        #expect(context.precedingText == "Hello ")
        #expect(context.followingText == " world")
        #expect(context.selection == TextSelection(location: 6, length: 9))
    }

    @Test func editingWithoutSelectionIsRefused() {
        let element = FakeTextElement(text: "Hello")
        let driver = FakeAccessibilityDriver(focused: element)

        let capture = reader(driver).read(for: FakeAccessibilityDriver.target(for: element), purpose: .editing)

        #expect(capture == .blocked(.noSelection, purpose: .editing))
        #expect(element.textReads.isEmpty)
    }

    @Test func overLongSelectionIsRefusedNotTruncated() {
        let element = FakeTextElement(text: String(repeating: "a", count: CursorContext.maxSelectionLength + 1))
        element.select(TextSelection(location: 0, length: CursorContext.maxSelectionLength + 1))
        let driver = FakeAccessibilityDriver(focused: element)

        let capture = reader(driver).read(for: FakeAccessibilityDriver.target(for: element), purpose: .editing)

        #expect(capture == .blocked(.selectionTooLong, purpose: .editing))
        #expect(element.textReads.isEmpty)
    }

    @Test func secureFieldIsNeverRead() {
        var behavior = FakeTextElement.Behavior()
        behavior.isSecure = true
        let element = FakeTextElement(text: "hunter2", behavior: behavior)
        let driver = FakeAccessibilityDriver(focused: element)

        for purpose in [ContextPurpose.formatting, .editing] {
            let capture = reader(driver).read(for: FakeAccessibilityDriver.target(for: element), purpose: purpose)
            #expect(capture == .blocked(.secureField, purpose: purpose))
        }
        #expect(!driver.readSecureField)
        #expect(element.textReads.isEmpty)
    }

    @Test func secureInputBlocks() {
        let element = FakeTextElement(text: "Hello")
        let driver = FakeAccessibilityDriver(focused: element)
        driver.setSecureInput(true)

        let capture = reader(driver).read(for: FakeAccessibilityDriver.target(for: element), purpose: .formatting)

        #expect(capture == .blocked(.secureInput, purpose: .formatting))
        #expect(element.textReads.isEmpty)
    }

    @Test func excludedAppIsNeverRead() {
        let element = FakeTextElement(text: "Private notes")
        let driver = CountingDriver(FakeAccessibilityDriver(focused: element))
        let policy = ContextPolicy(
            usesFormattingContext: true, allowsVoiceEditing: true, excludedApplications: ["com.example.Editor"])
        let reader = CursorContextReader(driver: driver, policy: { policy })

        let excluded = reader.read(for: FakeAccessibilityDriver.target(for: element), purpose: .formatting)
        let sensitive = reader.read(
            for: FakeAccessibilityDriver.target(for: element, bundleIdentifier: "com.bitwarden.desktop"),
            purpose: .editing)

        #expect(excluded == .blocked(.excludedApp, purpose: .formatting))
        #expect(sensitive == .blocked(.sensitiveApp, purpose: .editing))
        #expect(driver.calls == 0)
    }

    @Test func switchedOffFormattingReadsNothing() {
        let element = FakeTextElement(text: "Hello")
        let driver = CountingDriver(FakeAccessibilityDriver(focused: element))
        let reader = CursorContextReader(driver: driver, policy: { .default })

        let capture = reader.read(for: FakeAccessibilityDriver.target(for: element), purpose: .formatting)

        #expect(capture == .blocked(.disabled, purpose: .formatting))
        #expect(driver.calls == 0)
    }

    @Test func unreadableFieldProceedsWithoutContext() {
        var behavior = FakeTextElement.Behavior()
        behavior.exposesText = false
        let element = FakeTextElement(text: "Hello", behavior: behavior)
        let driver = FakeAccessibilityDriver(focused: element)

        let capture = reader(driver).read(for: FakeAccessibilityDriver.target(for: element), purpose: .formatting)

        #expect(capture == .blocked(.unreadable, purpose: .formatting))
    }

    @Test func appReturningTooMuchTextIsIgnored() {
        var behavior = FakeTextElement.Behavior()
        behavior.overreadsBy = 500
        let element = FakeTextElement(text: String(repeating: "a", count: 900), behavior: behavior)
        element.select(TextSelection(location: 300, length: 0))
        let driver = FakeAccessibilityDriver(focused: element)

        let capture = reader(driver).read(for: FakeAccessibilityDriver.target(for: element), purpose: .formatting)

        #expect(capture == .blocked(.unreadable, purpose: .formatting))
    }

    @Test func missingTrustOrElementIsReported() {
        let element = FakeTextElement(text: "Hello")
        let untrusted = FakeAccessibilityDriver(trusted: false, focused: element)
        #expect(
            reader(untrusted).read(for: FakeAccessibilityDriver.target(for: element), purpose: .formatting)
                == .blocked(.noAccessibility, purpose: .formatting))
        let driver = FakeAccessibilityDriver(focused: element)
        #expect(
            reader(driver).read(for: FakeAccessibilityDriver.target(for: nil), purpose: .formatting)
                == .blocked(.unreadable, purpose: .formatting))
    }
}

/// Counts every driver call, to prove policy checks happen before any access.
private final class CountingDriver: AccessibilityDriving {
    private let base: FakeAccessibilityDriver
    private let count = Mutex(0)

    init(_ base: FakeAccessibilityDriver) { self.base = base }

    var calls: Int { count.withLock { $0 } }

    private func note() { count.withLock { $0 += 1 } }

    func isTrusted() -> Bool {
        note()
        return base.isTrusted()
    }
    func element(from reference: any FocusedElementReference) -> FakeTextElement? {
        note()
        return base.element(from: reference)
    }
    func focusedElement() -> (element: FakeTextElement, processIdentifier: Int32)? {
        note()
        return base.focusedElement()
    }
    func frontmostProcessIdentifier() -> Int32? {
        note()
        return base.frontmostProcessIdentifier()
    }
    func isSameElement(_ lhs: FakeTextElement, _ rhs: FakeTextElement) -> Bool { base.isSameElement(lhs, rhs) }
    func isSecureTextField(_ element: FakeTextElement) -> Bool {
        note()
        return base.isSecureTextField(element)
    }
    func isSecureInputActive() -> Bool {
        note()
        return base.isSecureInputActive()
    }
    func canSetSelectedText(_ element: FakeTextElement) -> Bool {
        note()
        return base.canSetSelectedText(element)
    }
    func characterCount(of element: FakeTextElement) -> Int? {
        note()
        return base.characterCount(of: element)
    }
    func selection(of element: FakeTextElement) -> TextSelection? {
        note()
        return base.selection(of: element)
    }
    func setSelectedText(_ text: String, on element: FakeTextElement) -> Bool {
        note()
        return base.setSelectedText(text, on: element)
    }
    func text(in range: TextSelection, of element: FakeTextElement) -> String? {
        note()
        return base.text(in: range, of: element)
    }
}
