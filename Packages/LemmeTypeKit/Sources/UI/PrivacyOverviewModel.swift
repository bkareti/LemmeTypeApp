import Domain
import Foundation
import Observation

/// What Delete All Local Data removed, in counts only.
public struct LocalDataErasure: Equatable, Sendable {
    public var historyEntries = 0
    public var personalizationItems = 0
    public var diagnosticsEvents = 0
    public var modelsRemoved = 0

    public init() {}

    public var isEmpty: Bool {
        historyEntries == 0 && personalizationItems == 0 && diagnosticsEvents == 0 && modelsRemoved == 0
    }
}

/// Settings › Privacy › Overview (E6-S5): Delete All Local Data.
///
/// Removes the history, the personalization library, any leftover session
/// audio, and the in-memory diagnostics. Downloaded models stay unless the user
/// also chooses to remove them. Safe to repeat.
@MainActor
@Observable
public final class PrivacyOverviewModel {
    /// Also remove downloaded models. Off by default: they are large and not private.
    public var removesModels = false
    public private(set) var isErasing = false
    /// The result of the last erase, until the next one.
    public private(set) var lastErasure: LocalDataErasure?

    private let history: HistorySettingsModel
    private let personalization: PersonalizationModel
    private let modes: ModesSettingsModel
    private let capture: any AudioCapturing
    private let modelAssets: any ModelAssetManaging
    private let clearDiagnostics: @MainActor () -> Int

    public init(
        history: HistorySettingsModel,
        personalization: PersonalizationModel,
        modes: ModesSettingsModel,
        capture: any AudioCapturing,
        modelAssets: any ModelAssetManaging,
        clearDiagnostics: @escaping @MainActor () -> Int
    ) {
        self.history = history
        self.personalization = personalization
        self.modes = modes
        self.capture = capture
        self.modelAssets = modelAssets
        self.clearDiagnostics = clearDiagnostics
    }

    /// A sentence the pane shows and announces after an erase.
    public var resultMessage: String? {
        guard let result = lastErasure else { return nil }
        guard !result.isEmpty else {
            return String(localized: "There was nothing left to delete.", bundle: .module)
        }
        var parts: [String] = []
        if result.historyEntries > 0 {
            parts.append(String(localized: "\(result.historyEntries) saved dictations", bundle: .module))
        }
        if result.personalizationItems > 0 {
            parts.append(
                String(localized: "\(result.personalizationItems) vocabulary, snippet, and mode items", bundle: .module)
            )
        }
        if result.diagnosticsEvents > 0 {
            parts.append(String(localized: "\(result.diagnosticsEvents) diagnostic events", bundle: .module))
        }
        if result.modelsRemoved > 0 {
            parts.append(String(localized: "\(result.modelsRemoved) downloaded models", bundle: .module))
        }
        return String(
            localized: "Deleted: \(parts.formatted(.list(type: .and))).", bundle: .module,
            comment: "Lists what Delete All Local Data removed")
    }

    public func eraseAll() async {
        guard !isErasing else { return }
        isErasing = true
        defer { isErasing = false }
        var result = LocalDataErasure()

        await history.refresh()
        result.historyEntries = history.entries.count
        await history.deleteAll()

        if !personalization.hasLoaded { await personalization.load() }
        result.personalizationItems = PersonalizationSummary(personalization.library).total
        await personalization.deleteAll()
        modes.refresh()

        await capture.purgeLeftovers()
        result.diagnosticsEvents = clearDiagnostics()

        if removesModels {
            for asset in ModelCatalog.all where await modelAssets.state(of: asset.id) != .notInstalled {
                if (try? await modelAssets.remove(asset.id)) != nil { result.modelsRemoved += 1 }
            }
        }
        lastErasure = result
    }

    public func dismissResult() {
        lastErasure = nil
    }
}
