import Domain
import Foundation

/// Serialises a report exactly as it will be previewed and saved.
public enum DiagnosticsReportEncoder {
    public static func encode(_ report: DiagnosticsReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    public static func text(for report: DiagnosticsReport) -> String {
        (try? encode(report)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
    }
}
