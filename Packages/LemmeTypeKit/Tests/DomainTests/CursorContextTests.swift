import Domain
import TestSupport
import Testing

/// E3-S1: the context model and the app-level policy.
struct CursorContextTests {
    @Test func capsAndRejectsLongSelections() {
        let caret = TextSelection(location: 0, length: 0)
        let longest = String(repeating: "a", count: CursorContext.maxPrecedingLength)
        #expect(CursorContext(precedingText: longest, followingText: "", selection: caret) != nil)
        #expect(CursorContext(precedingText: longest + "a", followingText: "", selection: caret) == nil)
        #expect(
            CursorContext(
                precedingText: "", followingText: String(repeating: "b", count: CursorContext.maxFollowingLength + 1),
                selection: caret) == nil)
        let selection = String(repeating: "c", count: CursorContext.maxSelectionLength + 1)
        #expect(CursorContext(precedingText: "", followingText: "", selection: caret, selectedText: selection) == nil)
        #expect(CursorContext.maxPrecedingLength == 240)
        #expect(CursorContext.maxFollowingLength == 40)
        #expect(CursorContext.maxSelectionLength == 4_000)
    }

    @Test func descriptionIsRedacted() throws {
        let canary = "CANARY-CONTEXT-5d21"
        let context = try #require(
            CursorContext(
                precedingText: canary, followingText: canary, selection: TextSelection(location: 19, length: 0),
                selectedText: canary))
        let capture = ContextCapture.captured(context, purpose: .formatting)

        #expect(!"\(context)".contains(canary))
        #expect(!String(reflecting: context).contains(canary))
        #expect(!"\(capture)".contains(canary))
        #expect(capture.identifier == "captured")
    }
}

struct ContextPolicyTests {
    @Test func formattingIsOffAndEditingOnByDefault() {
        let policy = ContextPolicy.default
        #expect(policy.blockReason(for: .formatting, bundleIdentifier: "com.apple.TextEdit") == .disabled)
        #expect(policy.blockReason(for: .editing, bundleIdentifier: "com.apple.TextEdit") == nil)
    }

    @Test func switchesControlEachPurpose() {
        let policy = ContextPolicy(usesFormattingContext: true, allowsVoiceEditing: false)
        #expect(policy.blockReason(for: .formatting, bundleIdentifier: "com.apple.Notes") == nil)
        #expect(policy.blockReason(for: .editing, bundleIdentifier: "com.apple.Notes") == .editingDisabled)
    }

    @Test(arguments: [ContextPurpose.formatting, .editing])
    func excludedAndSensitiveAppsBlockEveryPurpose(purpose: ContextPurpose) {
        let policy = ContextPolicy(
            usesFormattingContext: true, allowsVoiceEditing: true, excludedApplications: ["com.tinyspeck.slackmacgap"])
        #expect(policy.blockReason(for: purpose, bundleIdentifier: "com.tinyspeck.slackmacgap") == .excludedApp)
        #expect(policy.blockReason(for: purpose, bundleIdentifier: "com.1password.1password") == .sensitiveApp)
        #expect(policy.blockReason(for: purpose, bundleIdentifier: "com.apple.keychainaccess") == .sensitiveApp)
        #expect(policy.blockReason(for: purpose, bundleIdentifier: "com.apple.Passwords") == .sensitiveApp)
        #expect(policy.blockReason(for: purpose, bundleIdentifier: nil) == nil)
    }

    @Test func sensitiveAppsCannotBeReEnabledByExclusionsOrSwitches() {
        let policy = ContextPolicy(usesFormattingContext: true, allowsVoiceEditing: true, excludedApplications: [])
        for app in ContextPolicy.sensitiveApplications {
            #expect(policy.blockReason(for: .editing, bundleIdentifier: app) == .sensitiveApp)
        }
    }

    @Test func reasonIdentifiersAreStable() {
        let identifiers = ContextBlockReason.allCases.map(\.rawValue)
        #expect(identifiers.allSatisfy(DiagnosticValue.isSafeIdentifier))
        #expect(
            identifiers == [
                "disabled", "editing-disabled", "excluded-app", "sensitive-app", "secure-field", "secure-input",
                "no-accessibility", "unreadable", "no-selection", "selection-too-long",
            ])
        #expect(ContextCapture.notRequested.identifier == "not-requested")
    }

    @Test func preferencesExposeThePolicy() {
        let preferences = FakePreferences(
            usesFormattingContext: true, allowsVoiceEditing: false, contextExcludedApplications: ["com.example.A"])
        #expect(
            preferences.contextPolicy
                == ContextPolicy(
                    usesFormattingContext: true, allowsVoiceEditing: false, excludedApplications: ["com.example.A"]))
    }
}
