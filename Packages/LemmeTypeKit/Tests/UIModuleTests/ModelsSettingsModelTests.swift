import Domain
import Foundation
import TestSupport
import Testing

@testable import UI

/// E5-S2: the Models pane's model.
@MainActor
struct ModelsSettingsModelTests {
    private static let mac16GB = HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 16 << 30)

    private func makeModel(
        assets: FakeModelAssetManager = FakeModelAssetManager(), hardware: HardwareProfile = mac16GB,
        preferences: FakePreferences = FakePreferences(), engines: [any SpeechRecognitionEngine] = []
    ) -> ModelsSettingsModel {
        ModelsSettingsModel(modelAssets: assets, preferences: preferences, engines: engines, hardware: hardware)
    }

    @Test func listsEveryModelWithFitAndState() async {
        let model = makeModel(
            assets: FakeModelAssetManager(installed: [.whisperBaseEnglish]),
            hardware: HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 8 << 30))
        await model.refresh()
        #expect(model.rows.map(\.id) == [.whisperTinyEnglish, .whisperBaseEnglish, .whisperSmallEnglish])
        #expect(model.rows.map(\.fit) == [.recommended, .recommended, .supported])
        #expect(model.rows.map(\.state) == [.notInstalled, .installed, .notInstalled])
        #expect(model.usedBytes == ModelCatalog.whisperBaseEnglish.installedBytes)
        #expect(model.availableBytes == 50_000_000_000)
    }

    @Test func downloadNeedsConfirmationAndEnoughSpace() async {
        let assets = FakeModelAssetManager(availableBytes: 100)
        let model = makeModel(assets: assets)
        await model.offerDownload(of: .whisperSmallEnglish)
        #expect(model.downloadOffer?.asset.id == .whisperSmallEnglish)
        #expect(model.downloadOffer?.hasEnoughSpace == false)
        #expect(model.downloadOffer?.confirmationMessage.contains("Hugging Face") == true)
        model.confirmDownload()
        #expect(assets.installCount == 0)
        guard case .insufficientStorage(let required, let available) = model.modelError else {
            Issue.record("expected insufficient storage")
            return
        }
        #expect(required == ModelCatalog.whisperSmallEnglish.requiredFreeBytes)
        #expect(available == 100)
    }

    @Test func confirmedDownloadInstallsAndUpdatesTheRow() async {
        let assets = FakeModelAssetManager()
        let model = makeModel(assets: assets)
        var changes = 0
        model.onModelsChanged = { changes += 1 }
        await model.offerDownload(of: .whisperTinyEnglish)
        model.confirmDownload()
        await model.settle()
        #expect(assets.installCount == 1)
        #expect(model.rows.first { $0.id == .whisperTinyEnglish }?.state == .installed)
        #expect(changes == 1)
    }

    @Test func unsupportedModelsCantBeOffered() async {
        let model = makeModel(hardware: HardwareProfile(isAppleSilicon: false, physicalMemoryBytes: 32 << 30))
        await model.offerDownload(of: .whisperBaseEnglish)
        #expect(model.downloadOffer == nil)
        #expect(model.rows.allSatisfy { !$0.fit.canRun })
    }

    @Test func removingUnloadsTheEngineFirst() async {
        let engine = FakeRecognitionEngine(id: .whisper, assets: .downloadable(.whisperBaseEnglish))
        let assets = FakeModelAssetManager(installed: [.whisperBaseEnglish])
        let model = makeModel(assets: assets, engines: [engine])
        await model.refresh()
        await model.removeModel(.whisperBaseEnglish)
        #expect(engine.unloadCount == 1)
        #expect(assets.removeCount == 1)
        #expect(model.rows.first { $0.id == .whisperBaseEnglish }?.state == .notInstalled)
    }

    @Test func whisperChoicePersists() {
        let preferences = FakePreferences()
        let model = makeModel(preferences: preferences)
        #expect(model.whisperModel == .automatic)
        model.setWhisperModel(.specific(.whisperSmallEnglish))
        #expect(preferences.whisperModel == .specific(.whisperSmallEnglish))
    }
}

/// E5-S4/E5-S5/E5-S6: profile, idle unload, and conditions in the Models pane.
@MainActor
struct PerformanceSettingsTests {
    @Test func profileAndIdlePeriodPersistAndShapeThePlan() {
        let preferences = FakePreferences()
        let model = ModelsSettingsModel(modelAssets: FakeModelAssetManager(), preferences: preferences)
        #expect(model.profile == .automatic)
        #expect(model.idleUnload == .after(minutes: 5))
        #expect(model.plan.profile == .balanced)

        model.setProfile(.bestAccuracy)
        model.setIdleUnload(.never)
        #expect(preferences.performanceProfile == .bestAccuracy)
        #expect(preferences.modelIdleUnload == .never)
        #expect(model.plan.whisperModelOrder.first == .whisperSmallEnglish)
    }

    @Test func conditionsLowerThePlanAndSayWhy() {
        let model = ModelsSettingsModel(modelAssets: FakeModelAssetManager(), preferences: FakePreferences())
        model.update(SystemConditions(isLowPowerModeEnabled: true))
        #expect(model.plan.profile == .lowPower)
        #expect(model.plan.reduction == .lowPowerMode)
        model.update(SystemConditions(thermal: .critical))
        #expect(model.plan.reduction == .thermal)
        #expect(model.plan.reduction?.message == "Performance is reduced to keep your Mac cool.")
        model.update(.nominal)
        #expect(model.plan.reduction == nil)
    }
}
