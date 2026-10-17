import AppKit
import Domain
import UI

/// Settings models that need app identity from AppKit (context exclusions,
/// per-app modes) or several services (models).
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
            modelAssets: modelAssets, preferences: preferences, engines: recognitionEngines, diagnostics: diagnostics)
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
}
