import Domain
import Foundation
import Observation
import Support

/// Engine, language, writing mode, model installation, and clipboard
/// fallback for the Dictation pane and the status menu (E2-S9).
///
/// Changes are written to preferences immediately and are read when the next
/// recording starts, so an in-progress session is never affected.
@MainActor
@Observable
public final class DictationSettingsModel {
    /// One selectable engine as Settings shows it.
    public struct EngineRow: Identifiable, Equatable, Sendable {
        public let id: RecognitionEngineID
        public let location: ProcessingLocation
        public let languages: [String]
        public let assets: AssetRequirement
        public let capabilities: EngineCapabilities
        public let tasks: Set<RecognitionTask>
        public var availability: EngineAvailability
        /// Install state of the engine's downloadable model, if it has one.
        public var model: ModelInstallState?

        public var isReady: Bool { availability.isReady }
    }

    /// What the user confirms before a model download starts.
    public struct DownloadOffer: Equatable, Sendable {
        public let asset: ModelAsset
        public let availableBytes: Int64

        public var hasEnoughSpace: Bool { availableBytes >= asset.requiredFreeBytes }
    }

    public private(set) var rows: [EngineRow]
    public private(set) var writingMode: WritingMode
    /// `nil` means Automatic.
    public private(set) var selectedEngine: RecognitionEngineID?
    public private(set) var language: String
    /// Original text or English (E9-S3).
    public private(set) var speechOutput: SpeechOutput
    /// Whether the chosen language and output can run, for the next dictation.
    public private(set) var readiness: LanguageReadiness = .noEngine
    public private(set) var fallsBackToReadyEngine: Bool
    public private(set) var clipboardFallback: ClipboardFallbackPolicy
    /// Set while the download confirmation is showing.
    public var downloadOffer: DownloadOffer?
    public private(set) var modelError: ModelAssetError?

    private let engines: [any SpeechRecognitionEngine]
    private let modelAssets: any ModelAssetManaging
    private let preferences: any AppPreferences
    private let speechAuthorizer: (any SpeechRecognitionAuthorizing)?
    private let diagnostics: any DiagnosticsRecording
    private let hardware: HardwareProfile
    /// Which languages this build offers (ADR 0029).
    public let languageScope: LanguageScope
    private var downloads: [ModelAssetID: Task<Void, Never>] = [:]
    private var refreshTask: Task<Void, Never>?

    /// `engines` are in recommendation order, as the pipeline receives them.
    public init(
        engines: [any SpeechRecognitionEngine],
        modelAssets: any ModelAssetManaging,
        preferences: any AppPreferences,
        speechAuthorizer: (any SpeechRecognitionAuthorizing)? = nil,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics(),
        hardware: HardwareProfile = .current,
        languageScope: LanguageScope = .allLanguages
    ) {
        self.hardware = hardware
        self.languageScope = languageScope
        self.engines = engines
        self.modelAssets = modelAssets
        self.preferences = preferences
        self.speechAuthorizer = speechAuthorizer
        self.diagnostics = diagnostics
        writingMode = preferences.writingMode
        selectedEngine = preferences.selectedEngine
        language = preferences.dictationLanguage
        speechOutput = preferences.speechOutput
        fallsBackToReadyEngine = preferences.fallsBackToReadyEngine
        clipboardFallback = preferences.clipboardFallback
        rows = engines.map {
            EngineRow(
                id: $0.descriptor.id, location: $0.descriptor.location, languages: $0.descriptor.supportedLanguages,
                assets: $0.descriptor.assets, capabilities: $0.descriptor.capabilities, tasks: $0.descriptor.tasks,
                availability: .assetsMissing, model: nil)
        }
    }

    // MARK: Derived state

    /// The engine the next session will use, or `nil` when none can run.
    public var effectiveEngine: RecognitionEngineID? {
        switch choice {
        case .engine(let id): id
        case .unavailable, .noneAvailable: nil
        }
    }

    /// Why the next session can't start recognition, if it can't.
    public var blockedEngine: (id: RecognitionEngineID, availability: EngineAvailability)? {
        if case .unavailable(let id, let availability, _) = choice { return (id, availability) }
        return nil
    }

    public var hasReadyEngine: Bool { rows.contains { $0.isReady && !$0.id.isCloud } }

    /// Languages every listed engine can be asked for, in a stable order.
    public var languages: [String] {
        var seen: [String] = []
        for row in rows {
            for language in row.languages where !seen.contains(language) {
                seen.append(language)
            }
        }
        return seen
    }

    /// What Settings asks of an engine for the next dictation (E9-S3).
    public var need: RecognitionNeed {
        RecognitionNeed(language: language, task: .required(for: language, output: speechOutput))
    }

    /// The values the Language menu offers, in order: Automatic (when an
    /// engine can detect), English (with the regions Apple Speech offers), then
    /// the other evaluation languages an engine supports. An English-only
    /// ``languageScope`` offers the English values alone.
    public var languageChoices: [String] {
        let detects =
            languageScope.offers(language: SpokenLanguages.automatic)
            && rows.contains { $0.capabilities.contains(.languageDetection) }
        var choices: [String] = detects ? [SpokenLanguages.automatic] : []
        let regional = languages.filter { SpokenLanguages.isEnglish($0) && $0.contains("-") }
        choices += regional.isEmpty ? [SpokenLanguages.english.settingValue] : regional
        let others = SpokenLanguages.all.filter { !SpokenLanguages.isEnglish($0.code) }.map(\.settingValue)
        choices += others.filter { value in
            languageScope.offers(language: value) && rows.contains { supports($0, value) }
        }
        // A stored language that is no longer offered stays visible.
        return choices.contains(language) ? choices : choices + [language]
    }

    /// The "Text you get" values this build offers. With a single value the
    /// views hide the picker.
    public var speechOutputChoices: [SpeechOutput] { languageScope.speechOutputs }

    /// The status of the chosen language in the support matrix, if it has one.
    public var languageStatus: LanguageSupportStatus? {
        SpokenLanguages.isAutomatic(language) ? nil : LanguageSupportMatrix.status(of: language)
    }

    private var choice: EngineSelector.Choice {
        EngineSelector.choose(
            preferred: selectedEngine, fallsBackAutomatically: fallsBackToReadyEngine,
            candidates: rows.filter { supports($0, language, task: need.task) }.map { ($0.id, $0.availability) })
    }

    func supports(_ row: EngineRow, _ language: String, task: RecognitionTask = .transcribe) -> Bool {
        EngineDescriptor(
            id: row.id, supportedLanguages: row.languages, assets: row.assets, capabilities: row.capabilities,
            tasks: row.tasks
        ).supports(RecognitionNeed(language: language, task: task))
    }

    // MARK: Refresh

    /// Reads every engine's availability and model state. Cheap; called when
    /// Settings or the menu appears and after anything that can change it.
    public func refresh() async {
        let need = need
        for (index, engine) in engines.enumerated() {
            var row = rows[index]
            row.availability = await engine.availability(for: need)
            if case .downloadable(let asset) = engine.descriptor.assets, downloads[asset] == nil {
                row.model = await modelAssets.state(of: asset)
            }
            rows[index] = row
        }
        readiness = await LanguageReadiness.evaluate(
            language: language, output: speechOutput, engines: engines,
            preference: EnginePreference(selected: selectedEngine, fallsBackAutomatically: fallsBackToReadyEngine),
            hardware: hardware)
    }

    public func refreshInBackground() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.refresh() }
    }

    // MARK: Choices

    public func setWritingMode(_ mode: WritingMode) {
        writingMode = mode
        preferences.writingMode = mode
        // The Exact/Clean choice here picks the matching built-in default mode (E4-S5).
        preferences.dictationMode = DictationMode.builtIn(for: mode).id
        diagnostics.record(.recognition, "settings.writing-mode", ["mode": .id(mode.rawValue)])
    }

    public func selectEngine(_ id: RecognitionEngineID?) {
        selectedEngine = id
        preferences.selectedEngine = id
        diagnostics.record(.recognition, "settings.engine", ["engine": .id(id?.rawValue ?? "automatic")])
    }

    public func setLanguage(_ language: String) {
        self.language = language
        preferences.dictationLanguage = language
        diagnostics.record(
            .recognition, "settings.language",
            ["language": .id(SpokenLanguages.isAutomatic(language) ? language : SpokenLanguages.code(of: language))])
        refreshInBackground()
    }

    public func setSpeechOutput(_ output: SpeechOutput) {
        speechOutput = output
        preferences.speechOutput = output
        diagnostics.record(.recognition, "settings.speech-output", ["output": .id(output.rawValue)])
        refreshInBackground()
    }

    public func setFallsBackToReadyEngine(_ enabled: Bool) {
        fallsBackToReadyEngine = enabled
        preferences.fallsBackToReadyEngine = enabled
    }

    public func setClipboardFallback(_ fallback: ClipboardFallback) {
        clipboardFallback.fallback = fallback
        preferences.clipboardFallback = clipboardFallback
    }

    public func setRestoreDelay(_ seconds: Double) {
        clipboardFallback.restoreDelay = seconds
        preferences.clipboardFallback = clipboardFallback
    }

    // MARK: Speech Recognition authorization

    public var canRequestSpeechRecognition: Bool { speechAuthorizer != nil }

    /// Prompts once; afterwards opens System Settings.
    public func allowSpeechRecognition() async {
        guard let speechAuthorizer else { return }
        if speechAuthorizer.status() == .notRequested {
            _ = await speechAuthorizer.requestAuthorization()
        } else {
            speechAuthorizer.openSystemSettings()
        }
        await refresh()
    }

    // MARK: Models

    /// Shows the confirmation with sizes, licence, and free space.
    public func offerDownload(of asset: ModelAssetID) async {
        guard let model = ModelCatalog.asset(asset) else { return }
        modelError = nil
        downloadOffer = DownloadOffer(asset: model, availableBytes: await modelAssets.availableBytes())
    }

    /// Starts (or resumes) the download the user confirmed.
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
    public func resumeDownload(of asset: ModelAssetID) {
        guard let model = ModelCatalog.asset(asset) else { return }
        install(model)
    }

    public func pauseDownload(of asset: ModelAssetID) async {
        await modelAssets.pause(asset)
    }

    public func removeModel(_ asset: ModelAssetID) async {
        downloads[asset]?.cancel()
        downloads[asset] = nil
        do {
            try await modelAssets.remove(asset)
            modelError = nil
        } catch {
            modelError = error
        }
        await unloadEngine(using: asset)
        await refresh()
    }

    /// Frees the memory a loaded model uses; it reloads on next use.
    public func unloadEngine(using asset: ModelAssetID) async {
        for engine in engines where engine.descriptor.assets == .downloadable(asset) {
            await engine.unload()
        }
    }

    public func isDownloading(_ asset: ModelAssetID) -> Bool { downloads[asset] != nil }

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
                    self?.setModelState(state, for: id)
                }
            }
            do throws(ModelAssetError) {
                try await assets.install(consent) { continuation.yield($0) }
            } catch {
                self?.modelError = error
            }
            continuation.finish()
            await updates.value
            // Availability first, so observers see the engine ready when the
            // download stops being reported as in progress.
            await self?.refresh()
            self?.downloads[id] = nil
        }
    }

    private func setModelState(_ state: ModelInstallState, for asset: ModelAssetID) {
        guard let index = rows.firstIndex(where: { $0.assets == .downloadable(asset) }) else { return }
        rows[index].model = state
    }
}
