#if os(iOS)
    import SwiftUI

    /// Shown for the whole of a session whose audio goes to the cloud (ADR 0031).
    struct CloudSpeechNotice: View {
        let isVisible: Bool

        var body: some View {
            if isVisible {
                Label(
                    String(
                        localized: "Using Cloud speech: your voice is sent online", bundle: .module,
                        comment: "Shown while a recording uses the cloud speech engine"),
                    systemImage: "cloud.fill"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.blue)
                .accessibilityIdentifier("quick.cloud")
            }
        }

        /// What the alert before the microphone prompt says, true in both states.
        static func microphoneExplanation(cloudSpeechOn: Bool) -> String {
            cloudSpeechOn
                ? String(
                    localized:
                        "LemmeType listens only while you are on this screen and the recording is showing. Modes that use Cloud speech send your voice online; others keep it on this device. Next, iOS asks for your permission.",
                    bundle: .module,
                    comment: "Shown before iOS asks for microphone permission, when cloud speech is on")
                : String(
                    localized:
                        "LemmeType listens only while you are on this screen and the recording is showing. Your voice is turned into text on this device and never leaves it. Next, iOS asks for your permission.",
                    bundle: .module,
                    comment: "Shown before iOS asks for microphone and speech recognition permission")
        }
    }

    /// The Cloud speech section of Settings on iPhone and iPad (E12-S1).
    struct MobileCloudSpeechSection: View {
        @Bindable var model: CloudSpeechSettingsModel
        @State private var keyDraft = ""
        @State private var isConfirmingTurnOff = false

        var body: some View {
            Section {
                switch model.status {
                case .off: offRow
                case .needsKey: keyEntry
                case .turnedOn: onRows
                }
            } header: {
                Text(String(localized: "Cloud speech", bundle: .module, comment: "A settings section title"))
            } footer: {
                Text(
                    String(
                        localized:
                            "Off by default. When on, a mode can use the Cloud engine for more accurate Telugu. Modes that don’t choose it stay on this device.",
                        bundle: .module)
                )
            }
        }

        private var offRow: some View {
            Button(String(localized: "Turn On Cloud Speech…", bundle: .module), action: model.requestTurnOn)
                .accessibilityIdentifier("settings.cloud.turnOn")
                // On the row: a sheet attached to the whole Section never appears inside a List.
                .sheet(isPresented: $model.isShowingConsent) { consent }
        }

        private var keyEntry: some View {
            Group {
                SecureField(String(localized: "\(model.providerName) API key", bundle: .module), text: $keyDraft)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("settings.cloud.key")
                Button(String(localized: "Save Key", bundle: .module)) {
                    let key = keyDraft
                    keyDraft = ""
                    Task { await model.saveKey(key) }
                }
                .disabled(keyDraft.isEmpty)
                .accessibilityIdentifier("settings.cloud.saveKey")
                if let problem = model.keyProblem {
                    Text(message(for: problem)).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("settings.cloud.keyProblem")
                }
                turnOffButton
            }
        }

        private var onRows: some View {
            Group {
                Label(
                    String(localized: "On. Your key is saved on this device.", bundle: .module),
                    systemImage: "cloud.fill"
                )
                .accessibilityIdentifier("settings.cloud.status")
                turnOffButton
            }
        }

        private var turnOffButton: some View {
            Button(String(localized: "Turn Off and Remove Key", bundle: .module), role: .destructive) {
                isConfirmingTurnOff = true
            }
            .accessibilityIdentifier("settings.cloud.turnOff")
            .confirmationDialog(
                String(localized: "Turn off cloud speech?", bundle: .module), isPresented: $isConfirmingTurnOff,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Turn Off and Remove Key", bundle: .module), role: .destructive) {
                    Task { await model.turnOff() }
                }
                .accessibilityIdentifier("settings.cloud.confirmTurnOff")
            }
        }

        private var consent: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(
                            String(
                                localized:
                                    "If you turn this on, recordings made with the Cloud engine are sent to \(model.providerName) (\(model.host)) to be turned into text. They are processed in India.",
                                bundle: .module))
                        Text(
                            String(
                                localized:
                                    "Only the audio of those recordings is sent. Your vocabulary, your other modes, and anything else on this device are not.",
                                bundle: .module))
                        Text(
                            String(
                                localized:
                                    "You use your own \(model.providerName) API key and pay \(model.providerName) directly. Its terms decide how long your audio is kept.",
                                bundle: .module))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("settings.cloud.consent")
                }
                .navigationTitle(String(localized: "Send Audio to the Cloud?", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", bundle: .module), action: model.declineConsent)
                            .accessibilityIdentifier("settings.cloud.decline")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Agree", bundle: .module)) {
                            Task { await model.acceptConsent() }
                        }
                        .accessibilityIdentifier("settings.cloud.agree")
                    }
                }
            }
        }

        private func message(for problem: CloudSpeechSettingsModel.KeyProblem) -> String {
            switch problem {
            case .empty: String(localized: "Paste your API key first.", bundle: .module)
            case .notSaved: String(localized: "The key couldn’t be saved. Try again.", bundle: .module)
            }
        }
    }
#endif
