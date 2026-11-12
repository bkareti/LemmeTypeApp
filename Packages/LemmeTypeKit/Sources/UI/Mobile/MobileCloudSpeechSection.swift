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

    /// The Cloud speech section of Settings on iPhone and iPad (E12-S1, E13-S3). One switch and an agreement:
    /// there is no key to enter, because the LemmeType gateway holds it (ADR 0033).
    struct MobileCloudSpeechSection: View {
        @Bindable var model: CloudSpeechSettingsModel
        @State private var isConfirmingTurnOff = false

        var body: some View {
            Section {
                switch model.status {
                case .off: offRow
                case .needsConsentAgain: agreeAgainRows
                case .turnedOn: onRows
                }
            } header: {
                Text(String(localized: "Cloud speech", bundle: .module, comment: "A settings section title"))
            } footer: {
                Text(
                    String(
                        localized:
                            "Off by default. When on, a mode can use the Cloud engine for more accurate Telugu. It is part of your LemmeType subscription, with nothing to set up. Modes that don’t choose it stay on this device.",
                        bundle: .module, comment: "Explains cloud speech in Settings")
                )
            }
            .task {
                await model.verifyTerms()
                await model.refreshAllowance()
            }
        }

        private var offRow: some View {
            Group {
                Button(
                    String(
                        localized: "Turn On Cloud Speech…", bundle: .module,
                        comment: "Button that opens the agreement to send audio to the cloud"),
                    action: model.requestTurnOn
                )
                .accessibilityIdentifier("settings.cloud.turnOn")
                // On the row: a sheet attached to the whole Section never appears inside a List.
                .sheet(isPresented: $model.isShowingConsent) { consent }
                if let problem = model.problem {
                    Text(message(for: problem)).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("settings.cloud.problem")
                }
            }
        }

        private var agreeAgainRows: some View {
            Group {
                Text(
                    String(
                        localized:
                            "LemmeType’s speech service has changed. Agree again to keep using Cloud speech.",
                        bundle: .module, comment: "Shown when the cloud speech terms changed and need a new agreement")
                )
                .accessibilityIdentifier("settings.cloud.agreeAgain")
                Button(
                    String(
                        localized: "Review and Agree…", bundle: .module,
                        comment: "Button that opens the agreement again after the terms changed"),
                    action: model.requestTurnOn
                )
                .accessibilityIdentifier("settings.cloud.turnOn")
                .sheet(isPresented: $model.isShowingConsent) { consent }
                turnOffButton
            }
        }

        private var onRows: some View {
            Group {
                Label(
                    String(
                        localized: "On. Audio from Cloud modes is sent to LemmeType.", bundle: .module,
                        comment: "Status of cloud speech in Settings when it is on"),
                    systemImage: "cloud.fill"
                )
                .accessibilityIdentifier("settings.cloud.status")
                if let allowance = model.allowance {
                    Text(
                        String(
                            localized:
                                "About \(allowance.remainingMinutes) minutes of Cloud speech left until \(allowance.periodEnd.formatted(date: .abbreviated, time: .omitted)).",
                            bundle: .module, comment: "How much cloud speech allowance is left in this billing period")
                    )
                    .font(.footnote)
                    .accessibilityIdentifier("settings.cloud.allowance")
                }
                turnOffButton
            }
        }

        private var turnOffButton: some View {
            Button(
                String(
                    localized: "Turn Off Cloud Speech", bundle: .module,
                    comment: "Button that turns cloud speech off"), role: .destructive
            ) {
                isConfirmingTurnOff = true
            }
            .accessibilityIdentifier("settings.cloud.turnOff")
            .confirmationDialog(
                String(localized: "Turn off cloud speech?", bundle: .module), isPresented: $isConfirmingTurnOff,
                titleVisibility: .visible
            ) {
                Button(
                    String(
                        localized: "Turn Off Cloud Speech", bundle: .module,
                        comment: "Button that confirms turning cloud speech off"), role: .destructive
                ) {
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
                                    "If you turn this on, recordings made with the Cloud engine are sent to LemmeType’s server (\(model.host)), which passes them to a speech service in India to be turned into text.",
                                bundle: .module, comment: "First paragraph of the cloud speech agreement"))
                        Text(
                            String(
                                localized:
                                    "Only the audio of those recordings is sent. Your vocabulary, your other modes, and anything else on this device are not. LemmeType does not keep your audio or the text.",
                                bundle: .module, comment: "Second paragraph of the cloud speech agreement"))
                        Text(
                            String(
                                localized:
                                    "Cloud speech is part of your LemmeType subscription, with a monthly allowance. There is nothing to set up. How long the speech service keeps audio is set by its own terms.",
                                bundle: .module, comment: "Third paragraph of the cloud speech agreement"))
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

        private func message(for problem: CloudSpeechSettingsModel.Problem) -> String {
            switch problem {
            case .subscriptionRequired:
                String(
                    localized: "Cloud speech needs an active LemmeType subscription or free trial.", bundle: .module,
                    comment: "Shown when cloud speech is turned on without a subscription")
            case .offline:
                String(
                    localized: "Couldn’t reach LemmeType. Check your connection and try again.", bundle: .module,
                    comment: "Shown when cloud speech is turned on while offline")
            case .failed:
                String(
                    localized: "Couldn’t turn on Cloud speech. Try again.", bundle: .module,
                    comment: "Shown when turning on cloud speech fails for another reason")
            }
        }
    }
#endif
