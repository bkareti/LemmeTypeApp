import Domain
import Observation
import Support

/// Settings › Personalize › Modes and the status-menu mode picker (E4-S6,
/// E4-S7): the default mode, custom modes, and per-app rules. Everything is
/// read when the next recording starts.
@MainActor
@Observable
public final class ModesSettingsModel {
    /// One per-app rule as Settings shows it.
    public struct AppRuleRow: Identifiable, Equatable, Sendable {
        public let rule: AppModeRule
        public let applicationName: String
        public var id: AppModeRule.ID { rule.id }
    }

    /// What deleting a mode would change, for the confirmation.
    public struct DeletionImpact: Equatable, Sendable {
        public let isDefault: Bool
        public let applications: [String]
        public var needsConfirmation: Bool { isDefault || !applications.isEmpty }
    }

    public private(set) var defaultMode: DictationModeID

    private let personalization: PersonalizationModel
    private let preferences: any AppPreferences
    private let runningApplications: @MainActor () -> [ApplicationIdentity]
    private let applicationName: @MainActor (String) -> String?
    private let diagnostics: any DiagnosticsRecording

    /// Engines a mode may pick, in recommendation order.
    public let engines: [RecognitionEngineID]
    /// Languages a mode may pick.
    public let languages: [String]

    public init(
        personalization: PersonalizationModel,
        preferences: any AppPreferences,
        engines: [RecognitionEngineID] = [],
        languages: [String] = [],
        runningApplications: @escaping @MainActor () -> [ApplicationIdentity] = { [] },
        applicationName: @escaping @MainActor (String) -> String? = { _ in nil },
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.personalization = personalization
        self.preferences = preferences
        self.engines = engines
        self.languages = languages
        self.runningApplications = runningApplications
        self.applicationName = applicationName
        self.diagnostics = diagnostics
        defaultMode = preferences.dictationMode
    }

    // MARK: Modes

    /// Built-in modes, then custom ones.
    public var modes: [DictationMode] { personalization.library.allModes }

    public var customModes: [DictationMode] { personalization.library.modes }

    /// The default mode, falling back to Clean Writing if it was deleted elsewhere.
    public var currentDefault: DictationMode {
        personalization.library.mode(defaultMode) ?? .clean
    }

    public func setDefault(_ id: DictationModeID) {
        guard personalization.library.mode(id) != nil else { return }
        defaultMode = id
        preferences.dictationMode = id
        if let mode = personalization.library.mode(id), id.isBuiltIn {
            preferences.writingMode = mode.writingMode  // keeps Epic 2 readers in step
        }
        diagnostics.record(.personalization, "mode.default", ["mode": .id(id.diagnosticIdentifier)])
    }

    /// Re-reads the default (Settings › Dictation may have changed it).
    public func refresh() {
        defaultMode = preferences.dictationMode
    }

    /// Adds or updates a custom mode; the validation error, if any.
    @discardableResult
    public func save(_ mode: DictationMode) -> PersonalizationError? {
        personalization.save(mode)
    }

    /// Saves a custom copy named "<name> Copy" (numbered if taken) and returns it.
    @discardableResult
    public func duplicate(_ mode: DictationMode) -> DictationMode? {
        let base = String(localized: "\(mode.displayName) Copy", bundle: .module)
        let taken = Set(
            modes.map { PersonalizationText.key($0.name) } + modes.map { PersonalizationText.key($0.displayName) })
        var name = String(base.prefix(DictationMode.maximumNameLength))
        var number = 2
        while taken.contains(PersonalizationText.key(name)) {
            name = String("\(base) \(number)".prefix(DictationMode.maximumNameLength))
            number += 1
        }
        let copy = mode.duplicated(named: name)
        return personalization.save(copy) == nil ? copy : nil
    }

    public func deletionImpact(of id: DictationModeID) -> DeletionImpact {
        DeletionImpact(
            isDefault: defaultMode == id,
            applications: personalization.library.appRules(using: id).map { name(of: $0.bundleIdentifier) })
    }

    /// Deletes a custom mode and its app rules; a deleted default becomes Clean Writing.
    public func delete(_ id: DictationModeID) {
        guard !id.isBuiltIn else { return }
        if defaultMode == id {
            setDefault(.clean)
        }
        personalization.removeMode(id)
        diagnostics.record(.personalization, "mode.deleted")
    }

    // MARK: App rules

    public var appRules: [AppRuleRow] {
        personalization.library.appRules.map {
            AppRuleRow(rule: $0, applicationName: name(of: $0.bundleIdentifier))
        }
    }

    /// Running apps without a rule.
    public var candidates: [ApplicationIdentity] {
        let ruled = Set(personalization.library.appRules.map { $0.bundleIdentifier.lowercased() })
        return runningApplications()
            .filter { !ruled.contains($0.bundleIdentifier.lowercased()) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    public func addRule(for application: ApplicationIdentity, mode: DictationModeID) -> PersonalizationError? {
        let error = personalization.save(AppModeRule(bundleIdentifier: application.bundleIdentifier, mode: mode))
        if error == nil {
            diagnostics.record(.personalization, "mode.app-rule-added", ["mode": .id(mode.diagnosticIdentifier)])
        }
        return error
    }

    public func setMode(_ mode: DictationModeID, for rule: AppModeRule) {
        var updated = rule
        updated.mode = mode
        personalization.save(updated)
    }

    public func removeRule(_ id: AppModeRule.ID) {
        personalization.removeAppRule(id)
        diagnostics.record(.personalization, "mode.app-rule-removed")
    }

    private func name(of bundleIdentifier: String) -> String {
        applicationName(bundleIdentifier) ?? bundleIdentifier
    }
}
