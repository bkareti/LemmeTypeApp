import Domain
import Testing

/// E5-S5 and E5-S6: profiles map to documented plans; the system can lower them.
struct PerformancePlanTests {
    private func plan(
        _ profile: PerformanceProfile, _ conditions: SystemConditions = .nominal,
        idle: IdleUnloadPolicy = .default, processors: Int = 10
    ) -> PerformancePlan {
        PerformancePlan.make(profile: profile, conditions: conditions, idleUnload: idle, processors: processors)
    }

    @Test func eachProfileMapsToItsPlan() {
        let balanced = plan(.balanced)
        #expect(balanced.profile == .balanced)
        #expect(balanced.whisperModelOrder == [.whisperBaseEnglish, .whisperSmallEnglish, .whisperTinyEnglish])
        #expect(balanced.inferenceThreads == 8)
        #expect(balanced.usesGPU && balanced.warmsUpDuringRecording)
        #expect(balanced.idleUnload == .default)
        #expect(balanced.reduction == nil)

        let low = plan(.lowPower)
        #expect(low.whisperModelOrder.first == .whisperTinyEnglish)
        #expect(low.inferenceThreads == 2)
        #expect(!low.usesGPU && !low.warmsUpDuringRecording)
        #expect(low.idleUnload == .after(minutes: 1))

        let best = plan(.bestAccuracy)
        #expect(best.whisperModelOrder.first == .whisperSmallEnglish)
        #expect(best.usesGPU && best.warmsUpDuringRecording)
        #expect(plan(.bestAccuracy, processors: 4).inferenceThreads == 2)
    }

    @Test func automaticFollowsLowPowerMode() {
        #expect(plan(.automatic).profile == .balanced)
        let saving = plan(.automatic, SystemConditions(isLowPowerModeEnabled: true))
        #expect(saving.profile == .lowPower)
        #expect(saving.reduction == .lowPowerMode)
        // An explicit choice is kept in Low Power Mode.
        #expect(plan(.bestAccuracy, SystemConditions(isLowPowerModeEnabled: true)).profile == .bestAccuracy)
    }

    @Test func seriousOrCriticalHeatLowersEveryProfile() {
        for profile in PerformanceProfile.allCases {
            for thermal in [ThermalLevel.serious, .critical] {
                let hot = plan(profile, SystemConditions(thermal: thermal))
                #expect(hot.profile == .lowPower)
                #expect(hot.reduction == (profile == .lowPower ? nil : .thermal))
            }
            #expect(plan(profile, SystemConditions(thermal: .fair)).reduction != .thermal)
        }
    }

    @Test func lowPowerCapsTheIdlePeriodButKeepsShorterOnes() {
        #expect(plan(.lowPower, idle: .never).idleUnload == .after(minutes: 1))
        #expect(plan(.lowPower, idle: .after(minutes: 15)).idleUnload == .after(minutes: 1))
        #expect(plan(.balanced, idle: .never).idleUnload == .never)
        #expect(IdleUnloadPolicy.after(minutes: 5).duration == .seconds(300))
        #expect(IdleUnloadPolicy.never.duration == nil)
        for policy in IdleUnloadPolicy.choices {
            #expect(IdleUnloadPolicy(identifier: policy.identifier) == policy)
        }
        #expect(IdleUnloadPolicy(identifier: "after-0m") == nil)
    }

    @Test func whisperChoiceNeverFallsBackFromASpecificModel() {
        let installed: Set<ModelAssetID> = [.whisperTinyEnglish]
        let order: [ModelAssetID] = [.whisperBaseEnglish, .whisperTinyEnglish]
        #expect(
            WhisperModelChoice.automatic.resolve(order: order, isInstalled: installed.contains) == .whisperTinyEnglish)
        #expect(
            WhisperModelChoice.specific(.whisperBaseEnglish).resolve(order: order, isInstalled: installed.contains)
                == nil)
        #expect(WhisperModelChoice.automatic.preferredDownload(order: order) == .whisperBaseEnglish)
    }
}
