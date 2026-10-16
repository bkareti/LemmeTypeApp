import Domain
import Foundation
import Observation
import Support

/// Builds the diagnostics report for preview and saves it only when the user
/// chooses a location. There is no upload path.
@MainActor
@Observable
public final class DiagnosticsModel {
    public private(set) var preview: String?
    public private(set) var saveError: String?

    private let buffer: DiagnosticsBuffer
    private let permissions: PermissionsModel
    private let shortcut: ShortcutSettingsModel
    private let buildInfo: BuildInfo
    private let osVersion: String
    private let hardwareModel: String
    private var report: DiagnosticsReport?

    public init(
        buffer: DiagnosticsBuffer,
        permissions: PermissionsModel,
        shortcut: ShortcutSettingsModel,
        buildInfo: BuildInfo,
        osVersion: String = SystemInfo.osVersion,
        hardwareModel: String = SystemInfo.hardwareModel
    ) {
        self.buffer = buffer
        self.permissions = permissions
        self.shortcut = shortcut
        self.buildInfo = buildInfo
        self.osVersion = osVersion
        self.hardwareModel = hardwareModel
    }

    public func makeReport(now: Date = Date()) -> DiagnosticsReport {
        permissions.refresh()
        return DiagnosticsReport(
            generatedAt: now,
            appVersion: buildInfo.version,
            appBuild: buildInfo.build,
            osVersion: osVersion,
            hardwareModel: hardwareModel,
            permissions: Dictionary(
                uniqueKeysWithValues: PermissionKind.allCases.map {
                    ($0.rawValue, permissions.status(for: $0).rawValue)
                }),
            activationMode: shortcut.mode.rawValue,
            events: buffer.snapshot()
        )
    }

    /// Prepares exactly the content that Save will write.
    public func preparePreview() {
        let report = makeReport()
        self.report = report
        preview = DiagnosticsReportEncoder.text(for: report)
        saveError = nil
    }

    public func closePreview() {
        report = nil
        preview = nil
    }

    public var suggestedFileName: String {
        "LemmeType-Diagnostics-\(buildInfo.version).json"
    }

    /// Writes the previewed report to a user-chosen location.
    public func save(to url: URL) {
        guard let report else { return }
        do {
            try DiagnosticsReportEncoder.encode(report).write(to: url, options: .atomic)
            closePreview()
        } catch {
            saveError = String(localized: "The report couldn’t be saved. Choose another location.", bundle: .module)
        }
    }
}
