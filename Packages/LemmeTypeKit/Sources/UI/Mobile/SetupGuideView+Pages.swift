#if os(iOS)
    import Domain
    import SwiftUI

    /// The setup guide's steps (E8-S10).
    extension SetupGuideView {
        // MARK: Pages

        @ViewBuilder var page: some View {
            switch model.step {
            case .welcome: welcome
            case .microphone: microphone
            case .listening: listening
            case .anyApp: anyApp
            case .done: done
            }
        }

        func header(_ title: String, _ text: String) -> some View {
            VStack(spacing: 10) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        var welcome: some View {
            VStack(spacing: 32) {
                WelcomeIllustration().padding(.top, 24)
                header(
                    String(localized: "Welcome to LemmeType", bundle: .module, comment: "Setup guide title"),
                    String(
                        localized: "Speak, and LemmeType writes it for you. Setup takes about a minute.",
                        bundle: .module, comment: "Setup guide welcome text"))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("setup.welcome")
        }

        var microphone: some View {
            VStack(spacing: 28) {
                MicrophoneIllustration(status: model.microphone)
                header(
                    String(localized: "Allow the Microphone", bundle: .module, comment: "Setup guide step title"),
                    microphoneText)
                switch model.microphone {
                case .notRequested:
                    EmptyView()
                case .granted:
                    Label(
                        String(localized: "Microphone allowed", bundle: .module, comment: "Setup guide status"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(Color.setupJade)
                    .font(.headline)
                    .accessibilityIdentifier("setup.microphone.allowed")
                case .denied, .restricted, .notGranted:
                    VStack(spacing: 10) {
                        Text(
                            String(
                                localized: "The microphone is off for LemmeType. You can turn it on in Settings.",
                                bundle: .module, comment: "Setup guide: the microphone was not allowed")
                        )
                        .multilineTextAlignment(.center)
                        Button(
                            String(localized: "Open Settings", bundle: .module), action: model.openSettingsForMicrophone
                        )
                        .buttonStyle(.bordered)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("setup.microphone.denied")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("setup.microphone")
        }

        var microphoneText: String {
            model.hasAskedForMicrophone
                ? String(
                    localized: "LemmeType listens only while a recording is showing on screen.", bundle: .module,
                    comment: "Setup guide: why the microphone is needed, after the system prompt")
                : String(
                    localized:
                        "LemmeType listens only while a recording is showing on screen. Next, iOS asks for your permission.",
                    bundle: .module, comment: "Setup guide: why the microphone is needed, before the system prompt")
        }

        var listening: some View {
            VStack(spacing: 22) {
                ListeningIllustration(choice: model.choice, modelState: model.suggestedModelState)
                header(
                    String(
                        localized: "How Should LemmeType Listen?", bundle: .module, comment: "Setup guide step title"),
                    String(
                        localized: "Choose one now. You can change it in Settings at any time.", bundle: .module,
                        comment: "Setup guide: under the listening title"))
                VStack(spacing: 12) {
                    ForEach(model.listeningOptions, id: \.self) { option in
                        ListeningOptionRow(model: model, option: option)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("setup.listening")
        }

        var anyApp: some View {
            VStack(spacing: 24) {
                header(
                    String(localized: "Dictate in Any App", bundle: .module),
                    String(
                        localized:
                            "Start dictating without opening LemmeType: from the keyboard, the Action Button, or a tap on the back of your iPhone.",
                        bundle: .module, comment: "Setup guide: under the Dictate in Any App title"))
                AnyAppSetupCards()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("setup.anyApp")
        }

        var done: some View {
            VStack(spacing: 24) {
                DoneIllustration()
                header(
                    String(localized: "You’re All Set", bundle: .module, comment: "Last setup guide step title"),
                    String(
                        localized: "Tap Start Dictating, speak, then copy the text into any app.", bundle: .module,
                        comment: "Last setup guide step text"))
                VStack(alignment: .leading, spacing: 14) {
                    ChecklistRow(
                        title: String(localized: "Microphone", bundle: .module), readiness: model.microphoneReadiness)
                    ChecklistRow(title: listeningTitle, readiness: model.listeningReadiness)
                    if model.steps.contains(.anyApp) {
                        Label(
                            String(
                                localized: "Dictate in Any App is in Settings whenever you want it.", bundle: .module,
                                comment: "Setup guide checklist line"),
                            systemImage: "gearshape"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quinary, in: .rect(cornerRadius: 18))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("setup.done")
        }

        var listeningTitle: String {
            switch model.choice {
            case .onDevice: ListeningOptionRow.title(for: .onDevice)
            case .appleSpeech: ListeningOptionRow.title(for: .appleSpeech)
            case .cloud: ListeningOptionRow.title(for: .cloud)
            case .later, nil:
                String(localized: "How LemmeType listens", bundle: .module, comment: "Setup guide checklist line")
            }
        }
    }
#endif
