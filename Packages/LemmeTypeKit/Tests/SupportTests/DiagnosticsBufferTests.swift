import Domain
import Foundation
import Support
import Testing

struct DiagnosticsBufferTests {
    @Test func keepsOnlyTheMostRecentEvents() {
        let buffer = DiagnosticsBuffer(capacity: 3)
        for _ in 0..<5 {
            buffer.record(.lifecycle, "app.tick")
        }
        buffer.record(.audio, "capture.started", ["fallback": .flag(true)])

        let events = buffer.snapshot()
        #expect(events.count == 3)
        #expect(events.last?.name == "capture.started")
        #expect(events.last?.attributes["fallback"] == .flag(true))
    }

    @Test(arguments: [
        "Jane's MacBook Pro Microphone", "Hello world", "CANARY", "a b", "", "x/y", "über",
        String(repeating: "a", count: 65),
    ])
    func unsafeIdentifiersAreRedacted(raw: String) {
        let buffer = DiagnosticsBuffer()
        buffer.record(.audio, "capture.failed", ["error": .id(raw), "raw": .identifier(raw)])

        let attributes = buffer.snapshot().first?.attributes
        #expect(attributes?["error"] == .identifier(DiagnosticValue.redactedIdentifier))
        #expect(attributes?["raw"] == .identifier(DiagnosticValue.redactedIdentifier))
    }

    @Test(arguments: ["audio.device-disconnected", "push_to_talk", "failed.audio.interrupted", "mac16-1"])
    func safeIdentifiersAreKept(raw: String) {
        #expect(DiagnosticValue.id(raw) == .identifier(raw))
    }

    @Test func hardwareModelIsAModelIdentifier() {
        let model = SystemInfo.hardwareModel
        #expect(model.contains(","))
        #expect(!model.isEmpty)
    }
}
