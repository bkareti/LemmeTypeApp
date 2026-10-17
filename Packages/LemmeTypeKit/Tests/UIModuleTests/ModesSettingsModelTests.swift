import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E4-S6 and E4-S7: managing modes and app rules, and choosing the mode when
/// a recording starts.
@MainActor
struct ModesSettingsModelTests {
    private let slack = ApplicationIdentity(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack")
    private let mail = ApplicationIdentity(bundleIdentifier: "com.apple.mail", name: "Mail")

    private func makeModel(preferences: FakePreferences = FakePreferences()) -> (
        ModesSettingsModel, PersonalizationModel
    ) {
        let personalization = PersonalizationModel(store: FakePersonalizationStore())
        let model = ModesSettingsModel(
            personalization: personalization, preferences: preferences, engines: [.appleSpeech, .whisper],
            languages: ["en-US"], runningApplications: { [slack, mail] },
            applicationName: { id in [slack, mail].first { $0.bundleIdentifier == id }?.name })
        return (model, personalization)
    }

    @Test func existingWritingModeBecomesTheDefaultMode() {
        #expect(makeModel(preferences: FakePreferences(writingMode: .clean)).0.currentDefault == .clean)
        #expect(makeModel(preferences: FakePreferences(writingMode: .exact)).0.currentDefault == .exact)
    }

    @Test func choosingTheDefaultPersistsIt() {
        let preferences = FakePreferences()
        let (model, _) = makeModel(preferences: preferences)
        model.setDefault(.message)
        #expect(preferences.dictationMode == .message)
        #expect(preferences.writingMode == .clean)
        #expect(model.currentDefault == .message)
        model.setDefault(.newCustom())  // unknown: ignored
        #expect(model.currentDefault == .message)
    }

    @Test func duplicateNamesCopiesUniquely() throws {
        let (model, _) = makeModel()
        let first = try #require(model.duplicate(.message))
        let second = try #require(model.duplicate(.message))
        #expect(first.name == "Message Copy")
        #expect(second.name == "Message Copy 2")
        #expect(model.customModes.count == 2)
        #expect(model.modes.prefix(3).map(\.id) == [.exact, .clean, .message])
    }

    @Test func invalidModesAreNotSaved() {
        let (model, _) = makeModel()
        #expect(model.save(DictationMode(name: "")) == .empty(.modeName))
        #expect(model.save(DictationMode(name: "Message")) == .duplicate(.modeName))
        #expect(model.customModes.isEmpty)
    }

    @Test func deletingTheDefaultFallsBackToCleanAndRemovesItsRules() throws {
        let preferences = FakePreferences()
        let (model, _) = makeModel(preferences: preferences)
        let chat = DictationMode(name: "Chat")
        #expect(model.save(chat) == nil)
        model.setDefault(chat.id)
        model.addRule(for: slack, mode: chat.id)
        model.addRule(for: mail, mode: .exact)

        let impact = model.deletionImpact(of: chat.id)
        #expect(impact == .init(isDefault: true, applications: ["Slack"]))
        #expect(impact.needsConfirmation)

        model.delete(chat.id)
        #expect(model.currentDefault == .clean)
        #expect(preferences.dictationMode == .clean)
        #expect(model.appRules.map(\.applicationName) == ["Mail"])
        model.delete(.clean)  // built-ins can't be deleted
        #expect(model.modes.contains(.clean))
    }

    @Test func appRulesAddChangeAndRemove() throws {
        let (model, _) = makeModel()
        #expect(model.candidates.map(\.name) == ["Mail", "Slack"])
        #expect(model.addRule(for: slack, mode: .message) == nil)
        #expect(model.candidates.map(\.name) == ["Mail"])
        let row = try #require(model.appRules.first)
        #expect(row.applicationName == "Slack")
        model.setMode(.exact, for: row.rule)
        #expect(model.appRules.first?.rule.mode == .exact)
        model.removeRule(row.id)
        #expect(model.appRules.isEmpty)
    }

    @Test func recordingUsesTheAppRuleAndTheModesEngineAndLanguage() async throws {
        let preferences = FakePreferences(writingMode: .exact)
        let (model, personalization) = makeModel(preferences: preferences)
        let whisperMode = DictationMode(name: "Whisper UK", engine: .whisper, language: "en-GB", writingMode: .clean)
        #expect(model.save(whisperMode) == nil)
        model.addRule(
            for: ApplicationIdentity(bundleIdentifier: "com.apple.TextEdit", name: "TextEdit"), mode: whisperMode.id)

        let source = FakeAudioSource()
        let processor = RecordingSpy()
        let coordinator = RecordingCoordinator(
            capture: AudioCaptureService(
                source: source,
                storage: AudioSessionStorage(
                    directory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("LemmeTypeTests-Modes-\(UUID().uuidString)")),
                permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: FakeFeedback(), preferences: preferences,
            finishedDisplay: .milliseconds(10), personalization: { personalization.library })

        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        #expect(coordinator.activeDictationMode?.id == whisperMode.id)
        #expect(coordinator.activeModeSource == .appRule)
        model.setDefault(.message)  // mid-recording: affects only the next session
        source.emitTone(seconds: 0.3)
        coordinator.handle(.stop)
        await coordinator.settle()

        #expect(processor.modes == [.clean])
        #expect(processor.preferences == [EnginePreference(selected: .whisper)])
        #expect(processor.languages == ["en-GB"])

        // Without a target the default mode is used.
        coordinator.handle(.start(nil))
        await coordinator.settle()
        #expect(coordinator.activeDictationMode == .message)
        #expect(coordinator.activeModeSource == .default)
        coordinator.handle(.cancel)
        await coordinator.settle()
    }
}
