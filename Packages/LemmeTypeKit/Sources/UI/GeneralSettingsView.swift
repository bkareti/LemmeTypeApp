import Domain
import SwiftUI

struct GeneralSettingsView: View {
    let model: GeneralSettingsModel
    let updates: UpdatesSettingsModel
    let about: AboutModel

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
                Toggle(
                    String(localized: "Play sounds when recording starts and stops", bundle: .module),
                    isOn: Binding(get: { model.playsFeedbackSounds }, set: { model.setPlaysFeedbackSounds($0) })
                )
                .accessibilityIdentifier("settings.feedbackSounds")
            }
            Section(String(localized: "Updates", bundle: .module, comment: "Noun: new versions of LemmeType")) {
                LabeledContent(String(localized: "Version", bundle: .module)) {
                    Text(model.buildInfo.displayString)
                        .accessibilityIdentifier("build.version")
                }
                HStack {
                    Button(String(localized: "Check for Updates…", bundle: .module)) {
                        Task { await updates.check() }
                    }
                    .disabled(updates.isChecking)
                    .accessibilityIdentifier("updates.check")
                    if updates.availableRelease != nil {
                        Button(String(localized: "Open Download Page…", bundle: .module)) { updates.openReleasePage() }
                            .accessibilityIdentifier("updates.openPage")
                    }
                }
                Text(updates.summary)
                    .font(.callout)
                    .accessibilityIdentifier("updates.status")
                if let checked = updates.status.checkedAt {
                    Text(
                        String(
                            localized: "Last checked \(checked.formatted(date: .abbreviated, time: .shortened)).",
                            bundle: .module)
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("updates.checked")
                }
                Toggle(
                    String(localized: "Check once a week", bundle: .module),
                    isOn: Binding(get: { updates.checksWeekly }, set: { updates.setChecksWeekly($0) })
                )
                .accessibilityIdentifier("updates.weekly")
                Text(PrivacyText.updates)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(String(localized: "About and support", bundle: .module)) {
                LabeledContent(
                    String(
                        localized: "Channel", bundle: .module,
                        comment: "Noun: how this build was distributed, for example direct or development")
                ) {
                    Text(about.channel.rawValue).accessibilityIdentifier("about.channel")
                }
                LabeledContent(String(localized: "macOS", bundle: .module)) {
                    Text(about.osVersion).accessibilityIdentifier("about.macos")
                }
                LabeledContent(
                    String(
                        localized: "Mac", bundle: .module,
                        comment: "Label for the model of this computer, for example Mac16,1")
                ) {
                    Text(about.hardwareModel).accessibilityIdentifier("about.mac")
                }
                HStack {
                    Button(String(localized: "Copy Support Info", bundle: .module)) {
                        Task {
                            await about.copySupportInfo()
                            if let message = about.message { AccessibilityNotification.Announcement(message).post() }
                        }
                    }
                    .accessibilityIdentifier("about.copy")
                    Button(String(localized: "Report a Problem…", bundle: .module)) { about.reportProblem() }
                        .accessibilityIdentifier("about.report")
                }
                Text(
                    String(
                        localized:
                            "Report a Problem opens a GitHub form with only your version, macOS version, and Mac model filled in. To add more, save a report from the Diagnostics pane and attach it yourself.",
                        bundle: .module)
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task { await updates.refresh() }
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
