import Foundation

/// The user's performance choice (E5-S5). Raw values are stable.
public enum PerformanceProfile: String, CaseIterable, Codable, Sendable {
    /// Balanced, or Low Power while macOS Low Power Mode is on.
    case automatic
    case balanced
    case lowPower = "low-power"
    case bestAccuracy = "best-accuracy"
}

/// How long loaded models stay in memory after the last session (E5-S4).
public enum IdleUnloadPolicy: Equatable, Hashable, Codable, Sendable {
    case after(minutes: Int)
    case never

    public static let `default` = IdleUnloadPolicy.after(minutes: 5)
    /// The choices Settings offers.
    public static let choices: [IdleUnloadPolicy] = [
        .after(minutes: 1), .after(minutes: 5), .after(minutes: 15), .after(minutes: 60), .never,
    ]

    public var duration: Duration? {
        switch self {
        case .after(let minutes): .seconds(max(1, minutes) * 60)
        case .never: nil
        }
    }

    /// The shorter of two policies (Low Power caps the idle time).
    public func capped(at other: IdleUnloadPolicy) -> IdleUnloadPolicy {
        switch (self, other) {
        case (.never, _): other
        case (_, .never): self
        case (.after(let mine), .after(let theirs)): .after(minutes: min(mine, theirs))
        }
    }

    /// Stable identifier for diagnostics and preferences.
    public var identifier: String {
        switch self {
        case .after(let minutes): "after-\(minutes)m"
        case .never: "never"
        }
    }

    public init?(identifier: String) {
        if identifier == "never" {
            self = .never
        } else if identifier.hasPrefix("after-"), identifier.hasSuffix("m"),
            let minutes = Int(identifier.dropFirst("after-".count).dropLast()), minutes > 0
        {
            self = .after(minutes: minutes)
        } else {
            return nil
        }
    }
}

/// macOS thermal state, as reported by `ProcessInfo`. Raw values are stable.
public enum ThermalLevel: String, Comparable, CaseIterable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rank < rhs.rank }
}

/// Memory pressure the system reported. Raw values are stable.
public enum MemoryPressure: String, Sendable {
    case normal
    case warning
    case critical
}

/// The system state that performance decisions depend on (E5-S6).
public struct SystemConditions: Equatable, Sendable {
    public var isLowPowerModeEnabled: Bool
    public var thermal: ThermalLevel
    public var memoryPressure: MemoryPressure

    public init(
        isLowPowerModeEnabled: Bool = false, thermal: ThermalLevel = .nominal, memoryPressure: MemoryPressure = .normal
    ) {
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.thermal = thermal
        self.memoryPressure = memoryPressure
    }

    public static let nominal = SystemConditions()

    /// Serious or critical: heavy work makes it worse.
    public var isThermallyConstrained: Bool { thermal >= .serious }
}

/// Reports system conditions and their changes (E5-S6). The `Lifecycle`
/// implementation listens to memory-pressure, thermal, and power events.
public protocol SystemConditionsMonitoring: Sendable {
    var current: SystemConditions { get }
    /// Every change from now on, until the stream is dropped.
    func changes() -> AsyncStream<SystemConditions>
}

/// What a session will run with, derived from the profile and the system
/// (E5-S5, E5-S6). Pure: same inputs, same plan.
public struct PerformancePlan: Equatable, Sendable {
    /// Why the plan is lower than the chosen profile, if it is.
    public enum Reduction: String, Sendable {
        case lowPowerMode = "low-power-mode"
        case thermal
    }

    /// Balanced, Low Power, or Best Accuracy (never Automatic).
    public let profile: PerformanceProfile
    public let reduction: Reduction?
    /// Whisper models to use with the Automatic model choice, first installed wins.
    public let whisperModelOrder: [ModelAssetID]
    public let inferenceThreads: Int
    public let usesGPU: Bool
    /// Start loading the engine while the user speaks.
    public let warmsUpDuringRecording: Bool
    public let idleUnload: IdleUnloadPolicy

    public init(
        profile: PerformanceProfile, reduction: Reduction?, whisperModelOrder: [ModelAssetID], inferenceThreads: Int,
        usesGPU: Bool, warmsUpDuringRecording: Bool, idleUnload: IdleUnloadPolicy
    ) {
        self.profile = profile
        self.reduction = reduction
        self.whisperModelOrder = whisperModelOrder
        self.inferenceThreads = inferenceThreads
        self.usesGPU = usesGPU
        self.warmsUpDuringRecording = warmsUpDuringRecording
        self.idleUnload = idleUnload
    }

    /// Low Power keeps models at most this long.
    public static let lowPowerIdleCap = IdleUnloadPolicy.after(minutes: 1)
    public static let lowPowerThreads = 2

    /// The plan for `profile` under `conditions`. Inference uses all but two
    /// of `processors`, at most eight (two in Low Power).
    public static func make(
        profile: PerformanceProfile, conditions: SystemConditions, idleUnload: IdleUnloadPolicy,
        processors: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> PerformancePlan {
        var effective = profile
        var reduction: Reduction?
        if profile == .automatic {
            effective = conditions.isLowPowerModeEnabled ? .lowPower : .balanced
            if conditions.isLowPowerModeEnabled { reduction = .lowPowerMode }
        }
        if conditions.isThermallyConstrained && effective != .lowPower {
            effective = .lowPower
            reduction = .thermal
        }
        let fullThreads = max(1, min(8, processors - 2))
        switch effective {
        case .lowPower:
            return PerformancePlan(
                profile: .lowPower, reduction: reduction,
                whisperModelOrder: [.whisperTinyEnglish, .whisperBaseEnglish, .whisperSmallEnglish],
                inferenceThreads: min(lowPowerThreads, fullThreads), usesGPU: false, warmsUpDuringRecording: false,
                idleUnload: idleUnload.capped(at: lowPowerIdleCap))
        case .bestAccuracy:
            return PerformancePlan(
                profile: .bestAccuracy, reduction: reduction,
                whisperModelOrder: [.whisperSmallEnglish, .whisperBaseEnglish, .whisperTinyEnglish],
                inferenceThreads: fullThreads, usesGPU: true, warmsUpDuringRecording: true, idleUnload: idleUnload)
        case .balanced, .automatic:
            return PerformancePlan(
                profile: .balanced, reduction: reduction,
                whisperModelOrder: [.whisperBaseEnglish, .whisperSmallEnglish, .whisperTinyEnglish],
                inferenceThreads: fullThreads, usesGPU: true, warmsUpDuringRecording: true, idleUnload: idleUnload)
        }
    }
}

/// Which Whisper model runs (E5-S1): the plan's choice among installed
/// models, or one the user picked.
public enum WhisperModelChoice: Equatable, Hashable, Sendable {
    case automatic
    case specific(ModelAssetID)

    /// The model to run given what is installed; `nil` when nothing suitable is.
    /// A specific choice never falls back to another model.
    public func resolve(order: [ModelAssetID], isInstalled: (ModelAssetID) -> Bool) -> ModelAssetID? {
        switch self {
        case .specific(let id): isInstalled(id) ? id : nil
        case .automatic: order.first(where: isInstalled)
        }
    }

    /// The model whose download fixes a missing model.
    public func preferredDownload(order: [ModelAssetID]) -> ModelAssetID? {
        switch self {
        case .specific(let id): id
        case .automatic: order.first
        }
    }
}
