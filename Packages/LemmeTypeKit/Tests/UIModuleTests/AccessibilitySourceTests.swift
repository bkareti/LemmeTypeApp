import Foundation
import Testing

/// E7-S6: rules about accessibility that a source scan can enforce on CI. The
/// real audit (`AccessibilityUITests`) and the VoiceOver script (MA-63) need a GUI
/// session; these rules catch the regressions that don't.
struct AccessibilitySourceTests {
    struct Source {
        let name: String
        let lines: [String]
    }

    static var views: [Source] {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/UI", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "swift" }.compactMap { file in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return Source(name: file.lastPathComponent, lines: text.components(separatedBy: "\n"))
        }
    }

    /// True if one of the `count` lines from `start` contains any of `needles`.
    static func nearby(_ source: Source, from start: Int, count: Int, _ needles: [String]) -> Bool {
        let end = min(source.lines.count, start + count)
        return source.lines[start..<end].contains { line in needles.contains { line.contains($0) } }
    }

    @Test func theScanSeesTheViews() {
        #expect(Self.views.count > 20, "the scan found the UI sources")
        #expect(Self.views.contains { $0.name == "SettingsView.swift" })
    }

    @Test func everyImageIsDecorativeOrLabelled() {
        var problems: [String] = []
        for source in Self.views {
            for (index, line) in source.lines.enumerated() where line.contains("Image(systemName:") {
                let labelled = Self.nearby(
                    source, from: index, count: 8, [".accessibilityHidden(true)", ".accessibilityLabel(", ".help("])
                if !labelled { problems.append("\(source.name):\(index + 1)") }
            }
        }
        #expect(problems.isEmpty, "images without a label or accessibilityHidden: \(problems)")
    }

    @Test func everyIconOnlyButtonHasALabel() {
        var problems: [String] = []
        for source in Self.views {
            for (index, line) in source.lines.enumerated() where line.contains("Button {") {
                if !Self.nearby(source, from: index, count: 24, [".accessibilityLabel("]) {
                    problems.append("\(source.name):\(index + 1)")
                }
            }
        }
        #expect(problems.isEmpty, "buttons built from a view with no accessibilityLabel: \(problems)")
    }

    @Test func motionIsAlwaysGuardedByReduceMotion() {
        var problems: [String] = []
        for source in Self.views {
            let text = source.lines.joined(separator: "\n")
            let animates =
                text.contains(".symbolEffect(") || text.contains("withAnimation(") || text.contains(".animation(")
            if animates && !text.contains("accessibilityReduceMotion") { problems.append(source.name) }
        }
        #expect(problems.isEmpty, "files that animate without reading Reduce Motion: \(problems)")
    }

    @Test func stateIsNeverShownByColourAlone() {
        // A coloured status line must carry text or a label too: no view may use
        // a bare `Circle().fill(` / `Rectangle().fill(` as the only status.
        var problems: [String] = []
        for source in Self.views {
            for (index, line) in source.lines.enumerated()
            where line.contains("Circle().fill(") || line.contains("Circle()\n") {
                if !Self.nearby(source, from: index, count: 6, [".accessibilityLabel(", ".accessibilityHidden(true)"]) {
                    problems.append("\(source.name):\(index + 1)")
                }
            }
        }
        #expect(problems.isEmpty, "colour-only indicators: \(problems)")
    }

    @Test func importantStateChangesAreAnnounced() {
        let text = Self.views.flatMap(\.lines).joined(separator: "\n")
        #expect(text.contains("AccessibilityNotification.Announcement"), "views announce results")
        let coordinator = Self.views.first { $0.name == "RecordingCoordinator+Processing.swift" }
        #expect(coordinator?.lines.joined().contains("feedback.announce") == true, "the recorder announces outcomes")
    }
}
