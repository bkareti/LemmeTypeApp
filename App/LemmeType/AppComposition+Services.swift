import AppKit
import Domain
import Lifecycle
import Shortcuts
import UI
import Updates

/// Builders for the pieces of the app controller that need several services.
extension AppComposition {
    /// The dictation shortcut and, when voice editing is on, its shortcut.
    func makeActivationController() -> ActivationController {
        ActivationController(
            registrar: hotKeyRegistrar,
            targetCapturer: targetCapturer,
            shortcut: preferences.dictationShortcut ?? .defaultDictation,
            editShortcut: preferences.allowsVoiceEditing ? (preferences.voiceEditShortcut ?? .defaultVoiceEdit) : nil,
            mode: preferences.activationMode,
            diagnostics: diagnostics
        )
    }

    func makeRecorder(
        personalization: PersonalizationModel, residency: ModelResidencyController
    ) -> RecordingCoordinator {
        RecordingCoordinator(
            capture: audioCapture,
            processor: makeDictationProcessor(),
            feedback: SystemRecordingFeedback(preferences: preferences),
            preferences: preferences,
            speechAuthorizer: speechAuthorizer,
            textCopier: textCopier,
            history: history,
            personalization: { [weak personalization] in personalization?.library ?? .empty },
            residency: residency,
            diagnostics: diagnostics
        )
    }

    /// The update check never runs while a dictation session is active (ADR 0026).
    func makeUpdates(recorder: RecordingCoordinator) -> UpdatesController {
        let checker = UpdateChecker(
            feed: updateFeed, currentVersion: buildInfo.version, preferences: preferences,
            isSessionActive: { await recorder.hasActiveSession }, diagnostics: diagnostics)
        let model = UpdatesSettingsModel(
            checker: checker, preferences: preferences, appVersion: buildInfo.version,
            openPage: { NSWorkspace.shared.open($0) })
        return UpdatesController(checker: checker, model: model)
    }

    /// A marker folder that is new for every launch, so UI tests never see an old run's marker.
    static func temporarySentinel(version: String) -> LaunchSentinel {
        LaunchSentinel(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LemmeTypeUITesting-State-\(UUID().uuidString)", isDirectory: true),
            version: version)
    }

    static var distributionChannel: DistributionChannel {
        #if DEBUG
            .development
        #else
            .direct
        #endif
    }

    /// Identifiers and flags for the support report (E7-S5); nothing the user said or wrote.
    func makeSupportSnapshot(models: ModelsSettingsModel, recovery: RecoveryNoticeModel) -> SupportSnapshot {
        SupportSnapshot(
            channel: Self.distributionChannel, previousRunEndedUnexpectedly: recovery.previousRunEndedUnexpectedly,
            installedModels: models.rows.filter { $0.state == .installed }.map { $0.id.rawValue },
            dictationLanguage: preferences.dictationLanguage.lowercased(),
            speechOutput: preferences.speechOutput.rawValue,
            performanceProfile: preferences.performanceProfile.rawValue,
            historyRetention: preferences.historyRetention.rawValue,
            updateChecksWeekly: preferences.checksForUpdatesWeekly)
    }

    func makeAbout() -> AboutModel {
        AboutModel(
            buildInfo: buildInfo, channel: Self.distributionChannel, copier: textCopier,
            openPage: { NSWorkspace.shared.open($0) })
    }
}
