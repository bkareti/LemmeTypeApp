import Domain
import Foundation
import Testing

@testable import Support

/// E6-S6: only the listed fields can ever leave the app in a diagnostics report.
/// Adding a field, an event key, or a category is a privacy decision: this test
/// fails until the list below is updated on purpose (ADR 0008, ADR 0025).
struct DiagnosticsReportSchemaTests {
    static let sampleEvent = DiagnosticEvent(
        timestamp: Date(timeIntervalSince1970: 0), category: .history, name: "history.recorded",
        attributes: ["entries": .count(2), "retention": .id("one-week"), "ok": .flag(true), "took": .seconds(0.5)])

    static func keys(of data: Data) throws -> Set<String> {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    @Test func theReportHasExactlyTheReviewedTopLevelFields() throws {
        let report = DiagnosticsReport(
            generatedAt: Date(timeIntervalSince1970: 0), appVersion: "1.0", appBuild: "7", osVersion: "macOS",
            hardwareModel: "Mac16,1", permissions: ["microphone": "granted"], activationMode: "toggle",
            events: [Self.sampleEvent])
        let data = try DiagnosticsReportEncoder.encode(report)
        #expect(
            try Self.keys(of: data) == [
                "schemaVersion", "generatedAt", "appVersion", "appBuild", "distributionChannel", "osVersion",
                "hardwareModel", "permissions", "activationMode", "previousRunEndedUnexpectedly", "installedModels",
                "dictationLanguage", "speechOutput", "performanceProfile", "historyRetention", "updateChecksWeekly",
                "events",
            ])
    }

    @Test func anEventHasExactlyTheReviewedFields() throws {
        let data = try JSONEncoder().encode(Self.sampleEvent)
        #expect(try Self.keys(of: data) == ["timestamp", "category", "name", "attributes"])
    }

    @Test func theCategoriesAreTheReviewedOnes() {
        #expect(
            DiagnosticCategory.allCases.map(\.rawValue) == [
                "lifecycle", "permissions", "shortcut", "audio", "recorder", "recognition", "models", "delivery",
                "editing", "personalization", "history",
            ])
    }

    @Test func valuesCanOnlyBeIdentifiersCountsFlagsAndDurations() throws {
        let data = try JSONEncoder().encode(Self.sampleEvent.attributes)
        let text = try #require(String(data: data, encoding: .utf8))
        for kind in ["identifier", "count", "flag", "seconds"] {
            #expect(text.contains("\"\(kind)\""), "value kind \(kind)")
        }
        #expect(!text.contains("\"string\"") && !text.contains("\"text\""))
    }

    @Test func freeTextBecomesRedactedEverywhereAnIdentifierIsAccepted() {
        for raw in ["Has Spaces", "UPPER", "with/slash", "emoji🙂", String(repeating: "a", count: 65), ""] {
            #expect(DiagnosticValue.id(raw) == .identifier(DiagnosticValue.redactedIdentifier), "\(raw)")
        }
        #expect(DiagnosticValue.id("one-week") == .identifier("one-week"))
    }
}
