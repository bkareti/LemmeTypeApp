import AppKit
import Domain
import Recognition
import UI

/// Settings models that need app identity from AppKit (context exclusions,
/// per-app modes) or several services (models), and the performance plan
/// that Whisper and model residency read for every session (E5-S5).
extension AppComposition {
    func makeModes(personalization: PersonalizationModel, languages: [String]) -> ModesSettingsModel {
        ModesSettingsModel(
            personalization: personalization, preferences: preferences,
            engines: recognitionEngines.map(\.descriptor.id), languages: languages,
            runningApplications: Self.runningApplications, applicationName: Self.applicationName,
            diagnostics: diagnostics)
    }

    func makeModels(dictation: DictationSettingsModel) -> ModelsSettingsModel {
        let models = ModelsSettingsModel(
            modelAssets: modelAssets, preferences: preferences, engines: recognitionEngines, hardware: hardware,
            conditions: systemConditions.current, diagnostics: diagnostics)
        models.onModelsChanged = { [weak dictation] in dictation?.refreshInBackground() }
        return models
    }

    func makeContextSettings(shortcut: ShortcutSettingsModel) -> ContextSettingsModel {
        ContextSettingsModel(
            preferences: preferences, shortcut: shortcut, rewriter: textRewriter,
            runningApplications: Self.runningApplications, applicationName: Self.applicationName,
            diagnostics: diagnostics)
    }

    /// Regular apps that are running, for Settings › Context's exclusion list.
    private static func runningApplications() -> [ApplicationIdentity] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier
            else { return nil }
            return ApplicationIdentity(bundleIdentifier: id, name: app.localizedName ?? id)
        }
    }

    private static func applicationName(_ bundleIdentifier: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier).map {
            FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
        }
    }

    /// The Whisper model choice and the performance plan, read for every session (E5-S1, E5-S5).
    nonisolated static func whisperSettings(
        preferences: any AppPreferences, conditions: SystemConditions
    ) -> WhisperRunSettings {
        let plan = performancePlan(preferences: preferences, conditions: conditions)
        return WhisperRunSettings(
            choice: preferences.whisperModel, order: plan.whisperModelOrder, threads: plan.inferenceThreads,
            usesGPU: plan.usesGPU)
    }

    /// The plan for the next session: profile, idle setting, and the system now (E5-S5).
    nonisolated static func performancePlan(
        preferences: any AppPreferences, conditions: SystemConditions
    ) -> PerformancePlan {
        PerformancePlan.make(
            profile: preferences.performanceProfile, conditions: conditions, idleUnload: preferences.modelIdleUnload)
    }

    func makeResidency() -> ModelResidencyController {
        let preferences = self.preferences
        let conditions = systemConditions
        return ModelResidencyController(
            engines: recognitionEngines,
            plan: { Self.performancePlan(preferences: preferences, conditions: conditions.current) },
            diagnostics: diagnostics)
    }
}
