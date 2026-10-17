import AppKit
import Lifecycle
import Support

/// Owns launch-time work that SwiftUI scenes cannot express: single-instance
/// enforcement and requests from later launches.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var composition = AppComposition.make(
        arguments: ProcessInfo.processInfo.arguments,
        infoDictionary: Bundle.main.infoDictionary
    )
    private(set) lazy var controller = composition.makeAppController()
    private var instanceCoordinator: SingleInstanceCoordinator?

    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
            // A benchmark run is a separate, short-lived process (E2-S10).
            if AppComposition.benchmarkRequest(arguments: ProcessInfo.processInfo.arguments) != nil { return }
        #endif
        let coordinator = SingleInstanceCoordinator(bundleIdentifier: Bundle.main.bundleIdentifier ?? Log.subsystem)
        if coordinator.handOffToExistingInstanceIfNeeded() {
            NSApp.terminate(nil)
            return
        }
        coordinator.observeActivationRequests { [weak self] in
            self?.controller.showSettings()
        }
        instanceCoordinator = coordinator
        Log.lifecycle.info("Launched with \(self.composition.mode.rawValue, privacy: .public) services")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
            if let request = AppComposition.benchmarkRequest(arguments: ProcessInfo.processInfo.arguments) {
                Task { [composition] in exit(await composition.runBenchmark(request)) }
                return
            }
        #endif
        controller.launchFinished()
        if composition.showsSettingsOnLaunch {
            controller.showSettings()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller.applicationBecameActive()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controller.recorder.hasActiveSession else {
            return .terminateNow
        }
        Task {
            await controller.prepareToTerminate()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.showSettings()
        return false
    }
}
