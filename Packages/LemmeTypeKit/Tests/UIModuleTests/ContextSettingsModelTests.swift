import Domain
import TestSupport
import Testing

@testable import UI

/// E3-S6: Settings › Context.
@MainActor
struct ContextSettingsModelTests {
    private let preferences = FakePreferences()
    private let controller = FakeShortcutController(failures: [:])

    private func makeModel(rewriter: FakeTextRewriter? = FakeTextRewriter()) -> ContextSettingsModel {
        ContextSettingsModel(
            preferences: preferences,
            shortcut: ShortcutSettingsModel(controller: controller, preferences: preferences),
            rewriter: rewriter,
            runningApplications: {
                [
                    ApplicationIdentity(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack"),
                    ApplicationIdentity(bundleIdentifier: "com.1password.1password", name: "1Password"),
                    ApplicationIdentity(bundleIdentifier: "com.apple.Notes", name: "Notes"),
                ]
            },
            applicationName: {
                ["com.tinyspeck.slackmacgap": "Slack", "com.apple.keychainaccess": "Keychain Access"][$0]
            })
    }

    @Test func formattingSwitchIsStoredForTheNextActivation() {
        let model = makeModel()
        #expect(!model.usesFormattingContext)

        model.setFormattingContext(true)

        #expect(preferences.contextPolicy.usesFormattingContext)
        #expect(model.usesFormattingContext)
    }

    @Test func excludingAnAppBlocksAllContextAndRemovingRestoresIt() {
        let model = makeModel()
        #expect(model.candidates.map(\.name) == ["Notes", "Slack"])  // sensitive apps are not offered

        model.exclude(ApplicationIdentity(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack"))

        #expect(model.excludedApplications.map(\.name) == ["Slack"])
        #expect(model.candidates.map(\.name) == ["Notes"])
        for purpose in [ContextPurpose.formatting, .editing] {
            #expect(
                preferences.contextPolicy.blockReason(for: purpose, bundleIdentifier: "com.tinyspeck.slackmacgap")
                    == .excludedApp)
        }

        model.include("com.tinyspeck.slackmacgap")
        #expect(model.excludedApplications.isEmpty)
        #expect(preferences.contextExcludedApplications.isEmpty)
    }

    @Test func voiceEditingSwitchRegistersOrRemovesTheShortcut() {
        let model = makeModel()
        #expect(model.allowsVoiceEditing)

        model.setVoiceEditing(false)
        #expect(controller.editShortcut == nil)
        #expect(!preferences.allowsVoiceEditing)

        model.setVoiceEditing(true)
        #expect(controller.editShortcut == .defaultVoiceEdit)
        #expect(preferences.allowsVoiceEditing)
    }

    @Test func showsWhetherTheOnDeviceModelIsReady() async {
        let rewriter = FakeTextRewriter(availability: .notEnabled)
        let model = makeModel(rewriter: rewriter)

        model.refreshAvailability()
        await model.settle()
        #expect(model.rewriterAvailability == .notEnabled)
        #expect(model.rewriterAvailability?.userMessage.contains("Apple Intelligence") == true)

        rewriter.setAvailability(.ready)
        model.refreshAvailability()
        await model.settle()
        #expect(model.rewriterAvailability == .ready)
    }

    @Test func listsInstalledSensitiveApps() {
        #expect(makeModel().sensitiveApplications == ["Keychain Access"])
    }
}
