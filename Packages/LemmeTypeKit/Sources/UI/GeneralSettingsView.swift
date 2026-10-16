import Domain
import SwiftUI

struct GeneralSettingsView: View {
    let model: GeneralSettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "Launch at Login", bundle: .module),
                    isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
                )
                .disabled(!model.canChangeLaunchAtLogin)
                .accessibilityIdentifier("settings.launchAtLogin")

                if let note = loginItemNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.launchAtLogin.note")
                }
                if model.loginItemStatus == .requiresApproval || model.errorMessage != nil {
                    Button(String(localized: "Open Login Items Settings…", bundle: .module)) {
                        model.openLoginItemsSettings()
                    }
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings.launchAtLogin.error")
                }
            }
            Section {
                LabeledContent(String(localized: "Version", bundle: .module)) {
                    Text(model.buildInfo.displayString)
                        .accessibilityIdentifier("build.version")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var loginItemNote: String? {
        switch model.loginItemStatus {
        case .requiresApproval:
            String(localized: "Approve LemmeType in System Settings › Login Items to finish.", bundle: .module)
        case .unavailable:
            String(localized: "Move LemmeType to the Applications folder to enable Launch at Login.", bundle: .module)
        case .enabled, .disabled:
            nil
        }
    }
}
