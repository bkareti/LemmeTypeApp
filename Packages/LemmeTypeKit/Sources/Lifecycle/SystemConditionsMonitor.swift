import Domain
import Foundation
import Support
import Synchronization

/// Memory pressure, thermal state, and Low Power Mode from the system (E5-S6).
/// Needs no permission. Events carry levels only.
public final class SystemConditionsMonitor: SystemConditionsMonitoring {
    private struct State {
        var conditions: SystemConditions
        var subscribers: [UUID: AsyncStream<SystemConditions>.Continuation] = [:]
    }

    private let state: Mutex<State>
    private let queue = DispatchQueue(label: "com.lemmetype.system-conditions")
    // Written once at the end of init and read only in deinit, so no two
    // threads ever access it concurrently.
    private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []
    private let memorySource: any DispatchSourceMemoryPressure

    public init(center: NotificationCenter = .default) {
        state = Mutex(State(conditions: Self.read(memoryPressure: .normal)))
        memorySource = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
        memorySource.setEventHandler { [weak self] in
            guard let self else { return }
            let event = memorySource.data
            let level: MemoryPressure =
                event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
            update { $0.memoryPressure = level }
        }
        memorySource.resume()
        let names: [Notification.Name] = [
            ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.update { conditions in
                    let fresh = Self.read(memoryPressure: conditions.memoryPressure)
                    conditions.thermal = fresh.thermal
                    conditions.isLowPowerModeEnabled = fresh.isLowPowerModeEnabled
                }
            }
        }
    }

    deinit {
        memorySource.cancel()
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        state.withLock { state in
            for continuation in state.subscribers.values { continuation.finish() }
        }
    }

    public var current: SystemConditions { state.withLock { $0.conditions } }

    public func changes() -> AsyncStream<SystemConditions> {
        let (stream, continuation) = AsyncStream.makeStream(of: SystemConditions.self)
        let id = UUID()
        state.withLock { $0.subscribers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        return stream
    }

    private func update(_ change: (inout SystemConditions) -> Void) {
        let (changed, conditions, subscribers) = state.withLock { state in
            let before = state.conditions
            change(&state.conditions)
            return (before != state.conditions, state.conditions, Array(state.subscribers.values))
        }
        guard changed else { return }
        Log.lifecycle.info(
            "System conditions: thermal=\(conditions.thermal.rawValue, privacy: .public) memory=\(conditions.memoryPressure.rawValue, privacy: .public) lowPower=\(conditions.isLowPowerModeEnabled, privacy: .public)"
        )
        for subscriber in subscribers {
            subscriber.yield(conditions)
        }
    }

    private static func read(memoryPressure: MemoryPressure) -> SystemConditions {
        let info = ProcessInfo.processInfo
        let thermal: ThermalLevel =
            switch info.thermalState {
            case .nominal: .nominal
            case .fair: .fair
            case .serious: .serious
            case .critical: .critical
            @unknown default: .serious
            }
        return SystemConditions(
            isLowPowerModeEnabled: info.isLowPowerModeEnabled, thermal: thermal, memoryPressure: memoryPressure)
    }
}
