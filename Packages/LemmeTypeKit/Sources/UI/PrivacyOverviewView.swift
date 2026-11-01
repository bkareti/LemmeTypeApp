import SwiftUI

/// Settings › Privacy › Overview: what each permission is for, what is kept,
/// and Delete All Local Data (E6-S5). Plain words; the facts are in
/// `PrivacyText` and ADR 0025.
struct PrivacyOverviewView: View {
    let model: PrivacyOverviewModel
    let openContextSettings: () -> Void
    @State private var isConfirmingErase = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(PrivacyText.intro)
                    .accessibilityIdentifier("privacy.intro")

                GroupBox(String(localized: "Permissions", bundle: .module)) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(PermissionExplanation.all) { explanation in
                            DisclosureGroup(explanation.name) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(explanation.why)
                                    Text(explanation.reads)
                                    Text(explanation.never)
                                    Text(explanation.turnOff).foregroundStyle(.secondary)
                                }
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityIdentifier("privacy.permission.\(explanation.id)")
                        }
                    }
                    .padding(6)
                }

                GroupBox(String(localized: "Text near your cursor", bundle: .module)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(PrivacyText.contextExplanation)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(String(localized: "Open Context Settings", bundle: .module), action: openContextSettings)
                            .accessibilityIdentifier("privacy.openContext")
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(String(localized: "What LemmeType keeps", bundle: .module)) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(PrivacyText.dataItems) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.headline)
                                Text(item.what)
                                Text(
                                    "\(item.location) \(item.duration) \(item.removal)"
                                )
                                .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("privacy.dataItem.\(item.id)")
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(String(localized: "The internet and tracking", bundle: .module)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(PrivacyText.network).accessibilityIdentifier("privacy.network")
                        Text(PrivacyText.analytics).accessibilityIdentifier("privacy.analytics")
                        Text(PrivacyText.backups)
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(String(localized: "Delete everything", bundle: .module)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            String(
                                localized:
                                    "Removes your history, vocabulary, snippets, modes, any leftover recordings, and the diagnostics list from this Mac.",
                                bundle: .module)
                        )
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        Toggle(
                            String(localized: "Also remove downloaded models", bundle: .module),
                            isOn: Binding(get: { model.removesModels }, set: { model.removesModels = $0 })
                        )
                        .accessibilityIdentifier("privacy.removeModels")
                        Button(
                            String(localized: "Delete All Local Data…", bundle: .module), role: .destructive
                        ) {
                            isConfirmingErase = true
                        }
                        .disabled(model.isErasing)
                        .accessibilityIdentifier("privacy.deleteAllData")
                        if let message = model.resultMessage {
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("privacy.erasureResult")
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .confirmationDialog(
            String(localized: "Delete all local data?", bundle: .module), isPresented: $isConfirmingErase
        ) {
            Button(String(localized: "Delete All Local Data", bundle: .module), role: .destructive) {
                Task {
                    await model.eraseAll()
                    if let message = model.resultMessage { AccessibilityNotification.Announcement(message).post() }
                }
            }
        } message: {
            Text(
                String(
                    localized:
                        "This can’t be undone. Export your history or vocabulary first if you want a copy. Your settings and permissions stay as they are.",
                    bundle: .module))
        }
    }
}
