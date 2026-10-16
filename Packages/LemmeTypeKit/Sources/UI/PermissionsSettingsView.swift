import Domain
import SwiftUI

struct PermissionsSettingsView: View {
    let model: PermissionsModel

    var body: some View {
        Form {
            Section {
                ForEach(PermissionKind.allCases, id: \.self) { permission in
                    PermissionRow(permission: permission, model: model)
                }
            }
            Section(String(localized: "Availability", bundle: .module)) {
                ForEach(Capability.allCases, id: \.self) { capability in
                    LabeledContent(capability.displayName) {
                        Text(
                            model.isAvailable(capability)
                                ? String(localized: "Available", bundle: .module)
                                : String(localized: "Unavailable", bundle: .module)
                        )
                        .accessibilityIdentifier("capability.\(capability.rawValue)")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .pollsPermissions(model)
    }
}
