import Domain
import Foundation
import ModelAssets
import TestSupport
import Testing

@testable import UI

/// E6-S2: Local mode is network-silent. Complete sessions run through the real
/// coordinator, pipeline, and delivery with fakes at the operating-system edges
/// while `SocketWatch` looks for any internet socket the process opens. The
/// static half of the proof is `scripts/check-network-usage.sh`; the real-Mac
/// half is MA-31.
@MainActor
@Suite(.serialized)
struct NetworkSilenceTests {
    /// Opens (and returns) an IPv4 stream socket bound to the loopback address.
    private static func openLoopbackSocket() -> Int32 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = UInt32(0x7f00_0001).bigEndian
        address.sin_port = 0
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return descriptor
    }

    // MARK: The probe itself

    @Test func theProbeSeesASocketThatIsOpened() async {
        let watch = SocketWatch(interval: .milliseconds(1))
        let descriptor = Self.openLoopbackSocket()
        #expect(descriptor >= 0)
        try? await Task.sleep(for: .milliseconds(20))
        close(descriptor)
        let seen = watch.stop()
        #expect(seen.contains { $0.descriptor == descriptor && !$0.isIPv6 && $0.type == SOCK_STREAM })
    }

    @Test func theProbeReportsNothingWhenNothingIsOpened() async {
        let watch = SocketWatch(interval: .milliseconds(1))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(watch.stop().isEmpty)
    }

    @Test func aSocketThatWasAlreadyOpenIsNotNew() {
        let descriptor = Self.openLoopbackSocket()
        defer { close(descriptor) }
        let watch = SocketWatch(interval: .milliseconds(1))
        #expect(watch.stop().isEmpty)
    }

    // MARK: Full sessions

    @Test func everySessionTypeOpensNoInternetSocket() async throws {
        let watch = SocketWatch()
        var outcomes: [String] = []

        // Clean dictation that joins a sentence, using cursor context.
        let sentence = FakeTextElement(text: "Hello ", selection: TextSelection(location: 6, length: 0))
        let formatting = ContextEndToEndTests.Harness(field: sentence, spoken: "this is a test")
        await formatting.press(.defaultDictation)
        outcomes.append(sentence.text)
        formatting.cleanUp()

        // Exact dictation into an empty field.
        let exactField = FakeTextElement()
        let exact = ContextEndToEndTests.Harness(
            field: exactField, spoken: "plain words", mode: .exact,
            preferences: FakePreferences(usesFormattingContext: false))
        await exact.press(.defaultDictation)
        outcomes.append(exactField.text)
        exact.cleanUp()

        // Voice editing of a selection with the (fake) on-device model.
        let selection = FakeTextElement(
            text: "Please send the report today.", selection: TextSelection(location: 16, length: 6))
        let editing = ContextEndToEndTests.Harness(
            field: selection, spoken: "make it loud", rewriter: FakeTextRewriter())
        await editing.press(.defaultVoiceEdit)
        outcomes.append(selection.text)
        editing.cleanUp()

        // Tone and format rewrite with a review.
        let draft = FakeTextElement()
        let styled = try StyleRewritingEndToEndTests.Harness(
            field: draft, spoken: "send the report on Friday", style: StyleRewritingEndToEndTests.email,
            rewriter: FakeTextRewriter(script: .text("Hi,\n\nPlease send the report on Friday.\n\nThanks,")))
        await styled.dictate(into: draft)
        styled.coordinator.perform(.insertText)
        await styled.coordinator.settle()
        outcomes.append(draft.text)
        styled.cleanUp()

        // Speech in another language translated to English, reviewed, inserted.
        let translated = FakeTextElement()
        let translation = try StyleRewritingEndToEndTests.Harness(
            field: translated, spoken: "please send the report", style: .none, writing: .exact,
            rewriter: FakeTextRewriter(), language: "hi", output: .english)
        await translation.dictate(into: translated)
        translation.coordinator.perform(.insertText)
        await translation.coordinator.settle()
        outcomes.append(translated.text)
        translation.cleanUp()

        let opened = watch.stop()

        // Every session really ran, so a silent probe means silence, not idleness.
        #expect(outcomes.allSatisfy { !$0.isEmpty }, "sessions produced text: \(outcomes)")
        #expect(opened.isEmpty, "internet sockets opened during sessions: \(opened)")
    }

    @Test func owningTheRealModelStoreOpensNoSocket() async {
        let watch = SocketWatch()
        let store = ModelAssetStore.makeDefault(diagnostics: DiscardingDiagnostics())
        _ = await store.state(of: .whisperBaseEnglish)
        _ = await store.availableBytes()
        await store.removeUnusableFiles()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(watch.stop().isEmpty)
    }

    // MARK: Downloads need the user

    /// Only the two Settings models, behind their confirmation, may start a
    /// download. A session cannot reach `install`.
    @Test func onlyTheSettingsModelsCanStartADownload() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let allowed: Set<String> = ["ModelsSettingsModel.swift", "DictationSettingsModel.swift"]
        var callers: Set<String> = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let name = file.lastPathComponent
            if file.pathComponents.contains("TestSupport") { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("assets.install(") || text.contains("manager.install(") || text.contains("store.install(")
            {
                callers.insert(name)
            }
        }
        #expect(callers.isSubset(of: allowed), "unexpected callers of install: \(callers.subtracting(allowed))")
        #expect(!callers.isEmpty, "the scan found no callers; update this test with the code")
    }
}
