import Domain
import Foundation
import Testing

@testable import Lifecycle

/// E5-S6: the real monitor reads the system state without any permission.
/// Memory and thermal events can't be raised on CI; see MA-45.
struct SystemConditionsMonitorTests {
    @Test func readsTheCurrentStateAndStartsWithoutPressure() {
        let monitor = SystemConditionsMonitor(center: NotificationCenter())
        #expect(monitor.current.memoryPressure == .normal)
        #expect(monitor.current.isLowPowerModeEnabled == ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    @Test func powerNotificationsRefreshTheState() async {
        let center = NotificationCenter()
        let monitor = SystemConditionsMonitor(center: center)
        let changes = monitor.changes()
        // The posted notification re-reads the system; with nothing changed no event is sent.
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        let next = Task { await changes.first { _ in true } }
        try? await Task.sleep(for: .milliseconds(50))
        next.cancel()
        #expect(monitor.current.thermal.rawValue.isEmpty == false)
    }
}
