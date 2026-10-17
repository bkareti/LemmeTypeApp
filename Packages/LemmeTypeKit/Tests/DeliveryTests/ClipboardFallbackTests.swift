import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Delivery

/// Clipboard fallback with restoration (E2-S8).
struct ClipboardFallbackTests {
    /// A field that ignores Accessibility writes, like a Chromium or Electron app.
    static func ignoringField(text: String = "", exposesCount: Bool = true) -> FakeTextElement {
        var behavior = FakeTextElement.Behavior()
        behavior.appliesWrites = false
        behavior.exposesCount = exposesCount
        return FakeTextElement(text: text, behavior: behavior)
    }

    static let previous: [[String: Data]] = [
        [
            FakePasteboard.plainText: Data("user's copy".utf8),
            "public.rtf": Data("{\\rtf1 user's copy}".utf8),
        ],
        ["public.png": Data([0x89, 0x50, 0x4E, 0x47])],
        ["public.file-url": Data("file:///Users/ana/report.pdf".utf8)],
    ]

    struct Harness {
        let field: FakeTextElement
        let driver: FakeAccessibilityDriver
        let pasteboard: FakePasteboard
        let keystroke: FakePasteKeystroke
        let diagnostics = RecordingDiagnostics()
        var policy = ClipboardFallbackPolicy.default

        init(
            field: FakeTextElement = ClipboardFallbackTests.ignoringField(),
            pasteboard: FakePasteboard = FakePasteboard(items: ClipboardFallbackTests.previous),
            consumes: Bool = true, succeeds: Bool = true,
            afterPaste: @escaping @Sendable (FakePasteboard) -> Void = { _ in }
        ) {
            self.field = field
            driver = FakeAccessibilityDriver(focused: field)
            self.pasteboard = pasteboard
            keystroke = FakePasteKeystroke(
                pasteboard: pasteboard, driver: driver, consumes: consumes, succeeds: succeeds,
                afterPaste: { afterPaste(pasteboard) })
        }

        func deliver(_ text: String, target: ActivationTarget? = nil) async -> DeliveryOutcome {
            let policy = policy
            return await DictationTextDelivery(
                driver: driver, pasteboard: pasteboard, keystroke: keystroke, policy: { policy },
                diagnostics: diagnostics, sleep: { _ in }
            ).deliver(text, to: target ?? FakeAccessibilityDriver.target(for: field))
        }
    }

    @Test func pastesOnceAndRestoresEveryClipboardType() async {
        let harness = Harness()

        let outcome = await harness.deliver("Hello there.")

        #expect(outcome == .delivered(.paste))
        #expect(harness.keystroke.postCount == 1)
        #expect(harness.field.pastes == ["Hello there."])
        #expect(harness.field.text == "Hello there.")
        // Plain text, rich text, an image, and a file URL all come back.
        #expect(harness.pasteboard.items == Self.previous)
        #expect(harness.pasteboard.restoreCount == 1)
    }

    @Test func slowTargetIsWaitedFor() async {
        var behavior = FakeTextElement.Behavior()
        behavior.appliesWrites = false
        behavior.readsBeforeChangeIsVisible = 5  // takes several polls to show the paste
        let harness = Harness(field: FakeTextElement(behavior: behavior))

        #expect(await harness.deliver("slow") == .delivered(.paste))
        #expect(harness.pasteboard.items == Self.previous)
        let pasted = harness.diagnostics.events.first { $0.name == "clipboard.pasted" }
        #expect(pasted?.attributes["consumed"] == .flag(true))
    }

    @Test func timedOutPasteRestoresAndKeepsTheTranscript() async {
        let harness = Harness(consumes: false)

        #expect(await harness.deliver("lost?") == .problem(.pasteTimedOut))
        #expect(harness.pasteboard.items == Self.previous)
        // The pipeline keeps the transcript for Copy Text on any problem.
        #expect(DictationIssue.deliveryFailed(.pasteTimedOut).actions(alternatives: []) == [.copyText, .discard])
    }

    @Test func unobservableTargetsWaitTheConfiguredDelayThenRestore() async {
        let delays = SleepLog()
        let field = Self.ignoringField(exposesCount: false)
        let driver = FakeAccessibilityDriver(focused: field)
        let pasteboard = FakePasteboard(items: Self.previous)
        let delivery = DictationTextDelivery(
            driver: driver, pasteboard: pasteboard,
            keystroke: FakePasteKeystroke(pasteboard: pasteboard, driver: driver),
            policy: { ClipboardFallbackPolicy(fallback: .pasteAndRestore, restoreDelay: 1) },
            sleep: { delays.append($0) })

        // Captured without an element (the app has no Accessibility focus), so
        // the paste can't be observed.
        let target = FakeAccessibilityDriver.target(for: nil, processIdentifier: field.processIdentifier)
        #expect(await delivery.deliver("x", to: target) == .delivered(.paste))
        #expect(delays.values.last == .seconds(1))
        #expect(pasteboard.items == Self.previous)
    }

    @Test func userClipboardChangeIsNeverOverwritten() async {
        let harness = Harness(afterPaste: { $0.userCopies("newer copy") })

        #expect(await harness.deliver("dictated") == .delivered(.paste))
        #expect(harness.pasteboard.string == "newer copy")
        #expect(harness.pasteboard.restoreCount == 0)
        #expect(harness.diagnostics.events.contains { $0.name == "clipboard.restore-skipped" })
    }

    @Test func unrestorableClipboardIsNeverTouched() async {
        let pasteboard = FakePasteboard(
            items: [["com.apple.pasteboard.promised-file-url": Data()]],
            unreadableTypes: ["com.apple.pasteboard.promised-file-url"])
        let harness = Harness(pasteboard: pasteboard)

        #expect(await harness.deliver("x") == .problem(.clipboardUnsupported))
        #expect(pasteboard.transientWriteCount == 0)
        #expect(harness.keystroke.postCount == 0)
        #expect(DictationIssue.deliveryFailed(.clipboardUnsupported).actions(alternatives: []).contains(.copyText))
    }

    @Test func emptyClipboardIsRestoredAsEmpty() async {
        let harness = Harness(pasteboard: FakePasteboard())
        #expect(await harness.deliver("x") == .delivered(.paste))
        #expect(harness.pasteboard.items.isEmpty)
    }

    @Test func failedKeystrokeRestoresAndReportsFailure() async {
        let harness = Harness(succeeds: false)
        #expect(await harness.deliver("x") == .problem(.failed))
        #expect(harness.pasteboard.items == Self.previous)
    }

    @Test func copyOnlyLeavesTheTextOnTheClipboard() async {
        var harness = Harness()
        harness.policy = ClipboardFallbackPolicy(fallback: .copyOnly)
        #expect(await harness.deliver("copy me") == .delivered(.copied))
        #expect(harness.pasteboard.string == "copy me")
        #expect(harness.keystroke.postCount == 0)
    }

    @Test func fallbackOffReportsTheInsertionProblem() async {
        var harness = Harness()
        harness.policy = ClipboardFallbackPolicy(fallback: .off)
        #expect(await harness.deliver("x") == .problem(.unsupported))
        #expect(harness.pasteboard.transientWriteCount == 0)
    }

    @Test func neverPastesWhereAccessibilityInsertionWasUnsafe() async {
        // Target changed, password field, secure input, no permission: no paste.
        let harness = Harness()
        harness.driver.focus(FakeTextElement())
        #expect(await harness.deliver("x") == .problem(.targetChanged))

        let secure = Harness()
        secure.driver.setSecureInput(true)
        #expect(await secure.deliver("x") == .problem(.secureField))

        let untrusted = Harness()
        untrusted.driver.setTrusted(false)
        #expect(await untrusted.deliver("x") == .problem(.permissionMissing))

        for harness in [harness, secure, untrusted] {
            #expect(harness.keystroke.postCount == 0)
            #expect(harness.pasteboard.items == Self.previous)
        }
    }

    @Test func directInsertionWinsSoTheClipboardIsUntouched() async {
        let harness = Harness(field: FakeTextElement())
        #expect(await harness.deliver("x") == .delivered(.accessibility))
        #expect(harness.pasteboard.transientWriteCount == 0)
    }

    @Test func targetCapturedWithoutAnElementPastesIntoTheSameApp() async {
        let harness = Harness()
        let target = FakeAccessibilityDriver.target(for: nil, processIdentifier: harness.field.processIdentifier)
        #expect(await harness.deliver("x", target: target) == .delivered(.paste))
    }

    @Test func clipboardContentsNeverReachDiagnostics() async {
        let pasteboard = FakePasteboard(items: [[FakePasteboard.plainText: Data("canary-clipboard".utf8)]])
        let harness = Harness(pasteboard: pasteboard)
        _ = await harness.deliver("canary-dictated")
        let events = String(describing: harness.diagnostics.events)
        #expect(!events.contains("canary"))
    }
}

/// Records requested sleeps without waiting.
final class SleepLog: Sendable {
    private let storage = Mutex<[Duration]>([])
    var values: [Duration] { storage.withLock { $0 } }
    func append(_ duration: Duration) { storage.withLock { $0.append(duration) } }
}
