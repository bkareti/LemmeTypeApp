import Domain
import Foundation
import Observation
import Support

/// Settings › Dictation › Models (E5-S2): every catalog model with its size,
/// languages, memory, fit for this Mac, and install state; download, pause,
/// resume, and remove; which Whisper model runs; and the performance profile
/// and idle unload (E5-S4, E5-S5) with the system conditions behind them (E5-S6).
@MainActor
@Observable
public final class ModelsSettingsModel {
    public struct Row: Identifiable, Equatable, Sendable {
        public let asset: ModelAsset
        public let fit: ModelFit
        public var state: ModelInstallState
        public var id: ModelAssetID { asset.id }
    }

    public typealias DownloadOffer = DictationSettingsModel.DownloadOffer

    public private(set) var rows: [Row]
    public private(set) var whisperModel: WhisperModelChoice
    public private(set) var availableBytes: Int64 = 0
    public private(set) var modelError: ModelAssetError?
    public private(set) var profile: PerformanceProfile
    public private(set) var idleUnload: IdleUnloadPolicy
    public private(set) var conditions: SystemConditions
    /// Set while the download confirmation is showing.
    public var downloadOffer: DownloadOffer?

    private let modelAssets: any ModelAssetManaging
    private let preferences: any AppPreferences
    private let engines: [any SpeechRecognitionEngine]
    private let diagnostics: any DiagnosticsRecording
    private var downloads: [ModelAssetID: Task<Void, Never>] = [:]
    /// Called after anything that can change engine availability.
    public var onModelsChanged: @MainActor () -> Void = {}

    public init(
        modelAssets: any ModelAssetManaging,
        preferences: any AppPreferences,
        engines: [any SpeechRecognitionEngine] = [],
        hardware: HardwareProfile = .current,
        catalog: [ModelAsset] = ModelCatalog.all,
        conditions: SystemConditions = .nominal,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.conditions = conditions
        profile = preferences.performanceProfile
        idleUnload = preferences.modelIdleUnload
        self.modelAssets = modelAssets
        self.preferences = preferences
        self.engines = engines
        self.diagnostics = diagnostics
        whisperModel = preferences.whisperModel
        rows = catalog.map { Row(asset: $0, fit: $0.hardware.fit(for: hardware), state: .notInstalled) }
    }

    // MARK: Derived

    /// Disk space used by installed models.
    public var usedBytes: Int64 {
        rows.filter { $0.state.isInstalled }.reduce(0) { $0 + $1.asset.installedBytes }
    }

    public var whisperRows: [Row] { rows.filter { $0.asset.engine == .whisper } }

    public func isDownloading(_ asset: ModelAssetID) -> Bool { downloads[asset] != nil }

    /// Quitting waits for these to pause so their progress is kept.
    public var hasActiveDownloads: Bool { !downloads.isEmpty }

    // MARK: Refresh

    public func refresh() async {
        for index in rows.indices where downloads[rows[index].id] == nil {
            rows[index].state = await modelAssets.state(of: rows[index].id)
        }
        availableBytes = await modelAssets.availableBytes()
    }

    // MARK: Performance (E5-S4, E5-S5, E5-S6)

    /// What the next session runs with, given the profile and the system now.
    public var plan: PerformancePlan {
        PerformancePlan.make(profile: profile, conditions: conditions, idleUnload: idleUnload)
    }

    public func setProfile(_ profile: PerformanceProfile) {
        self.profile = profile
        preferences.performanceProfile = profile
        diagnostics.record(
            .models, "settings.performance-profile",
            ["profile": .id(profile.rawValue), "effective": .id(plan.profile.rawValue)])
        onModelsChanged()
    }

    public func setIdleUnload(_ policy: IdleUnloadPolicy) {
        idleUnload = policy
        preferences.modelIdleUnload = policy
        diagnostics.record(.models, "settings.idle-unload", ["policy": .id(policy.identifier)])
    }

    /// The system's state changed (memory, heat, Low Power Mode).
    public func update(_ conditions: SystemConditions) {
        self.conditions = conditions
    }

    // MARK: Whisper model choice

    public func setWhisperModel(_ choice: WhisperModelChoice) {
        whisperModel = choice
        preferences.whisperModel = choice
        let id: String =
            switch choice {
            case .automatic: "automatic"
            case .specific(let asset): asset.rawValue
            }
        diagnostics.record(.models, "settings.whisper-model", ["model": .id(id)])
        onModelsChanged()
    }

    // MARK: Downloads

    /// Shows the confirmation with sizes, licence, fit, and free space.
    public func offerDownload(of id: ModelAssetID) async {
        guard let row = rows.first(where: { $0.id == id }), row.fit.canRun else { return }
        modelError = nil
        availableBytes = await modelAssets.availableBytes()
        downloadOffer = DownloadOffer(asset: row.asset, availableBytes: availableBytes)
    }

    /// Starts the download the user confirmed; refuses without enough space.
    public func confirmDownload() {
        guard let offer = downloadOffer else { return }
        downloadOffer = nil
        guard offer.hasEnoughSpace else {
            modelError = .insufficientStorage(
                requiredBytes: offer.asset.requiredFreeBytes, availableBytes: offer.availableBytes)
            return
        }
        install(offer.asset)
    }

    /// Resumes a paused download; the user already confirmed it.
    public func resumeDownload(of id: ModelAssetID) {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        install(row.asset)
    }

    public func pauseDownload(of id: ModelAssetID) async {
        await modelAssets.pause(id)
    }

    /// Pauses every active download so its progress is kept (quit, E5-S3).
    public func pauseAll() async {
        let active = downloads
        for id in active.keys {
            await modelAssets.pause(id)
        }
        for task in active.values {
            await task.value
        }
    }

    /// Unloads engines using the model first, so a loaded copy never outlives its file.
    public func removeModel(_ id: ModelAssetID) async {
        downloads[id]?.cancel()
        downloads[id] = nil
        for engine in engines where engine.descriptor.id == rows.first(where: { $0.id == id })?.asset.engine {
            await engine.unload()
        }
        do {
            try await modelAssets.remove(id)
            modelError = nil
        } catch {
            modelError = error
        }
        await refresh()
        onModelsChanged()
    }

    /// Waits for running downloads. For tests.
    public func settle() async {
        for task in Array(downloads.values) {
            await task.value
        }
    }

    private func install(_ asset: ModelAsset) {
        guard downloads[asset.id] == nil else { return }
        modelError = nil
        let consent = ModelDownloadConsent(asset: asset)
        let assets = modelAssets
        let id = asset.id
        let (progress, continuation) = AsyncStream.makeStream(of: ModelInstallState.self)
        downloads[id] = Task { [weak self] in
            let updates = Task { [weak self] in
                for await state in progress {
                    self?.setState(state, for: id)
                }
            }
            do throws(ModelAssetError) {
                try await assets.install(consent) { continuation.yield($0) }
            } catch {
                self?.modelError = error
            }
            continuation.finish()
            await updates.value
            self?.downloads[id] = nil
            await self?.refresh()
            self?.onModelsChanged()
        }
    }

    private func setState(_ state: ModelInstallState, for id: ModelAssetID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].state = state
    }
}
