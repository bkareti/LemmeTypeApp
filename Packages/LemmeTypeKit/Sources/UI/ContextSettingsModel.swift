import Domain
import Observation
import Support

/// An app the user can exclude from context: identifier plus display name.
public struct ApplicationIdentity: Hashable, Identifiable, Sendable {
    public let bundleIdentifier: String
    public let name: String

    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// Settings › Context (E3-S6): the formatting-context and voice-editing
/// switches, the on-device model status, built-in sensitive apps, and the
/// user's exclusion list. Changes are stored immediately and read by the
/// next activation (docs/decisions/0017-cursor-context.md).
@MainActor
@Observable
public final class ContextSettingsModel {
    public private(set) var usesFormattingContext: Bool
    public private(set) var allowsVoiceEditing: Bool
    public private(set) var excludedApplications: [ApplicationIdentity] = []
    /// Running apps that can still be excluded.
    public private(set) var candidates: [ApplicationIdentity] = []
    /// `nil` until checked.
    public private(set) var rewriterAvailability: RewriterAvailability?

    private let preferences: any AppPreferences
    private let shortcut: ShortcutSettingsModel
    private let rewriter: (any TextRewriting)?
    private let runningApplications: @MainActor () -> [ApplicationIdentity]
    private let applicationName: @MainActor (String) -> String?
    private let diagnostics: any DiagnosticsRecording
    private var availabilityTask: Task<Void, Never>?

    /// `runningApplications` lists regular apps that are running now;
    /// `applicationName` gives the display name for a bundle identifier.
    public init(
        preferences: any AppPreferences,
        shortcut: ShortcutSettingsModel,
        rewriter: (any TextRewriting)?,
        runningApplications: @escaping @MainActor () -> [ApplicationIdentity] = { [] },
        applicationName: @escaping @MainActor (String) -> String? = { _ in nil },
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.preferences = preferences
        self.shortcut = shortcut
        self.rewriter = rewriter
        self.runningApplications = runningApplications
        self.applicationName = applicationName
        self.diagnostics = diagnostics
        usesFormattingContext = preferences.usesFormattingContext
        allowsVoiceEditing = preferences.allowsVoiceEditing
        refreshApplications()
    }

    /// Built-in apps that never provide context, by display name when installed.
    public var sensitiveApplications: [String] {
        ContextPolicy.sensitiveApplications.compactMap(applicationName).sorted()
    }

    public func setFormattingContext(_ enabled: Bool) {
        preferences.usesFormattingContext = enabled
        usesFormattingContext = enabled
        diagnostics.record(.editing, "context.formatting", ["enabled": .flag(enabled)])
    }

    public func setVoiceEditing(_ enabled: Bool) {
        shortcut.setVoiceEditing(enabled)
        allowsVoiceEditing = preferences.allowsVoiceEditing
        diagnostics.record(.editing, "context.voice-editing", ["enabled": .flag(enabled)])
    }

    public func exclude(_ application: ApplicationIdentity) {
        guard !preferences.contextExcludedApplications.contains(application.bundleIdentifier) else { return }
        preferences.contextExcludedApplications.append(application.bundleIdentifier)
        diagnostics.record(.editing, "context.app-excluded")
        refreshApplications()
    }

    public func include(_ bundleIdentifier: String) {
        preferences.contextExcludedApplications.removeAll { $0 == bundleIdentifier }
        diagnostics.record(.editing, "context.app-included")
        refreshApplications()
    }

    /// Re-reads the exclusion list and running apps.
    public func refreshApplications() {
        let excluded = preferences.contextExcludedApplications
        excludedApplications = excluded.map {
            ApplicationIdentity(bundleIdentifier: $0, name: applicationName($0) ?? $0)
        }
        candidates = runningApplications()
            .filter { !excluded.contains($0.bundleIdentifier) && !ContextPolicy.isSensitive($0.bundleIdentifier) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Checks whether the on-device model can run, in the background.
    public func refreshAvailability() {
        guard let rewriter else {
            rewriterAvailability = .unavailable
            return
        }
        availabilityTask?.cancel()
        let language = preferences.dictationLanguage
        availabilityTask = Task { [weak self] in
            let availability = await rewriter.availability(language: language)
            guard !Task.isCancelled else { return }
            self?.rewriterAvailability = availability
        }
    }

    /// Waits for a pending availability check. For tests.
    public func settle() async {
        await availabilityTask?.value
    }
}
