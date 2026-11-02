import Domain
import Foundation
import Support
import TestSupport
import Testing

@testable import UI

/// E7-S5: what the About section copies and sends, and that the richer report
/// stays free of content and small.
@MainActor
struct SupportInfoTests {
    private func makeAbout(
        opened: @escaping @MainActor (URL) -> Void = { _ in }, copier: FakeTextDelivery = FakeTextDelivery()
    ) -> AboutModel {
        AboutModel(
            buildInfo: BuildInfo(version: "0.2.0", build: "7"), channel: .direct, copier: copier, openPage: opened,
            osVersion: "Version 27.0 (Build 27A266a)", hardwareModel: "Mac16,1")
    }

    @Test func supportInfoIsExactlyTheAboutFields() {
        #expect(
            makeAbout().supportInfo == """
                LemmeType 0.2.0 (7)
                Channel: direct
                macOS: Version 27.0 (Build 27A266a)
                Mac: Mac16,1
                """)
    }

    @Test func copyingPutsExactlyThatOnTheClipboard() async {
        let copier = FakeTextDelivery()
        let about = makeAbout(copier: copier)
        await about.copySupportInfo()
        #expect(copier.copied == [about.supportInfo])
        #expect(about.message != nil)
    }

    @Test func theProblemReportLinkHoldsOnlyTheFormAndFourFacts() throws {
        let url = try #require(makeAbout().problemReportURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https" && components.host == "github.com")
        #expect(components.path == "/bkareti/LemmeTypeApp/issues/new")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(Set(items.keys) == ["template", "version", "build", "macos", "mac"])
        #expect(items["template"] == "beta-feedback.yml")
        #expect(items["version"] == "0.2.0" && items["build"] == "7")
        #expect(items["macos"] == "Version 27.0 (Build 27A266a)" && items["mac"] == "Mac16,1")
    }

    @Test func reportAProblemOpensThatLinkAndNothingElse() throws {
        var opened: [URL] = []
        let about = makeAbout(opened: { opened.append($0) })
        about.reportProblem()
        #expect(opened == [try #require(about.problemReportURL)])
    }

    @Test func theIssueFormHasTheFieldsTheLinkFills() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let form = try String(
            contentsOf: sources.appendingPathComponent(".github/ISSUE_TEMPLATE/\(AboutModel.issueForm)"),
            encoding: .utf8)
        for field in ["version", "build", "macos", "mac"] {
            #expect(form.contains("id: \(field)\n"), "the form has a \(field) field")
        }
        #expect(form.contains("do **not** attach audio"))
    }

    // MARK: The report

    private func report(support: SupportSnapshot, events: [DiagnosticEvent] = []) -> DiagnosticsReport {
        DiagnosticsReport(
            generatedAt: Date(timeIntervalSince1970: 0), appVersion: "0.2.0", appBuild: "7", osVersion: "macOS",
            hardwareModel: "Mac16,1", permissions: ["microphone": "granted"], activationMode: "toggle", events: events,
            support: support)
    }

    @Test func theReportCarriesTheSupportFieldsAsIdentifiersAndFlags() throws {
        let support = SupportSnapshot(
            channel: .direct, previousRunEndedUnexpectedly: true,
            installedModels: ["whisper-small", "whisper-base-en"],
            dictationLanguage: "hi", speechOutput: "english", performanceProfile: "low-power",
            historyRetention: "one-week", updateChecksWeekly: true)
        let data = try DiagnosticsReportEncoder.encode(report(support: support))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 2)
        #expect(object["distributionChannel"] as? String == "direct")
        #expect(object["previousRunEndedUnexpectedly"] as? Bool == true)
        #expect(object["installedModels"] as? [String] == ["whisper-base-en", "whisper-small"])
        #expect(object["historyRetention"] as? String == "one-week")
        #expect(object["updateChecksWeekly"] as? Bool == true)
    }

    @Test func aFullEventBufferStaysUnderTheDocumentedSize() throws {
        let buffer = DiagnosticsBuffer()
        for index in 0..<(DiagnosticsBuffer.defaultCapacity + 100) {
            buffer.record(
                .recognition, "session.delivered",
                [
                    "engine": .id("whisper-base-en-0123456789-0123456789-0123456789-0123456789"),
                    "issue": .id("a-very-long-identifier-0123456789-0123456789-0123456789-0123456789"),
                    "audioSeconds": .seconds(Double(index)), "processingSeconds": .seconds(1.5),
                    "words": .count(index), "ok": .flag(true),
                ])
        }
        let data = try DiagnosticsReportEncoder.encode(report(support: .empty, events: buffer.snapshot()))
        #expect(buffer.snapshot().count == DiagnosticsBuffer.defaultCapacity)
        // Measured 391 KB with every identifier at its 64-character limit: real reports are far smaller.
        #expect(data.count < DiagnosticsReport.maximumEncodedBytes, "report is \(data.count) bytes")
    }
}
