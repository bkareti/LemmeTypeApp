import Domain
import Foundation
import Lifecycle
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E7-S4: after a kill the next launch starts clean, removes the dead run's
/// recording, and tells the user once.
@MainActor
struct CrashRecoveryEndToEndTests {
    @Test func aKilledRunLeavesNothingBehindAfterTheNextLaunch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-CrashRecovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("Sessions", isDirectory: true)
        let state = root.appendingPathComponent("State", isDirectory: true)

        // Run one: recording started, then the process was killed (no end(), file left).
        let firstRun = LaunchSentinel(directory: state, version: "0.1.0")
        _ = firstRun.begin()
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let leftover = sessions.appendingPathComponent("killed-mid-session.caf")
        try Data("CANARY-AUDIO".utf8).write(to: leftover)

        // Run two: the launch sequence of AppController.launchFinished.
        let capture = AudioCaptureService(
            source: FakeAudioSource(), storage: AudioSessionStorage(directory: sessions),
            permissions: FakePermissions(statuses: [.microphone: .granted]))
        let notice = RecoveryNoticeModel()
        let diagnostics = RecordingDiagnostics()
        let secondRun = LaunchSentinel(directory: state, version: "0.2.0")

        if case .endedUnexpectedly(let version) = secondRun.begin() {
            notice.show(previousVersion: version)
            diagnostics.record(.lifecycle, "lifecycle.unclean-exit", ["previousVersion": .id(version ?? "unknown")])
        }
        await capture.purgeLeftovers()

        #expect(notice.isVisible && notice.previousVersion == "0.1.0")
        #expect(diagnostics.events.map(\.name) == ["lifecycle.unclean-exit"])
        #expect(!FileManager.default.fileExists(atPath: leftover.path), "the dead run's recording is deleted")

        // Run two quits normally; run three sees nothing to report.
        secondRun.end()
        let thirdRun = LaunchSentinel(directory: state, version: "0.2.0")
        #expect(thirdRun.begin() == .endedNormally)
        #expect(!RecoveryNoticeModel().isVisible)
    }
}
