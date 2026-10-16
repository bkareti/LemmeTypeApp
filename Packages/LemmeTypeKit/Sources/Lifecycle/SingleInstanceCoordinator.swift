import AppKit
import Domain
import Support

/// Keeps one LemmeType per user session. A second launch asks the running
/// instance to come forward (over a local distributed notification) and exits.
@MainActor
public final class SingleInstanceCoordinator {
    static let activationRequest = Notification.Name("com.lemmetype.LemmeType.activationRequest")

    private let bundleIdentifier: String
    private var observer: (any NSObjectProtocol)?

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    /// Returns `true` if another instance should handle this launch. In that case
    /// the other instance has been asked to activate and the caller must terminate.
    public func handOffToExistingInstanceIfNeeded() -> Bool {
        let current = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .map { InstancePolicy.Instance(processIdentifier: $0.processIdentifier, launchDate: $0.launchDate) }
        let thisInstance = InstancePolicy.Instance(
            processIdentifier: current.processIdentifier, launchDate: current.launchDate)

        guard let existing = InstancePolicy.instanceToYieldTo(current: thisInstance, others: others) else {
            return false
        }

        Log.lifecycle.info(
            "Another instance is running; handing off to pid \(existing.processIdentifier, privacy: .public)")
        DistributedNotificationCenter.default().postNotificationName(
            Self.activationRequest,
            object: bundleIdentifier,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }

    /// Calls `handler` whenever a later launch hands off to this instance.
    public func observeActivationRequests(_ handler: @escaping @MainActor () -> Void) {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.activationRequest,
            object: bundleIdentifier,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    isolated deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}
