import AppKit
import SwiftUI

/// Foundation status window. Replaced by the menu-bar experience in E1-S2.
public struct StatusView: View {
    private let model: StatusViewModel

    public init(model: StatusViewModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Version", bundle: .module)) {
                    Text(model.buildInfo.displayString)
                        .accessibilityIdentifier("build.version")
                }
            }
            Section(String(localized: "Permissions", bundle: .module)) {
                ForEach(model.permissionRows) { row in
                    LabeledContent(row.permission.displayName) {
                        Text(row.status.displayName)
                            .accessibilityIdentifier("permission.\(row.permission.rawValue).status")
                    }
                }
            }
            Section(String(localized: "Audio", bundle: .module)) {
                LabeledContent(String(localized: "Input devices", bundle: .module)) {
                    Text(model.inputDeviceCount, format: .number)
                        .accessibilityIdentifier("audio.inputDeviceCount")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, minHeight: 280)
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.refresh()
        }
    }
}
