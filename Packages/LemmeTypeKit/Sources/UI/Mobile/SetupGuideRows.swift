#if os(iOS)
    import Domain
    import SwiftUI

    /// One way to listen, as a large tappable card that shows its own state.
    struct ListeningOptionRow: View {
        let model: SetupGuideModel
        let option: SetupGuideModel.Listening

        var body: some View {
            Button(action: choose) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.setupJade)
                        .frame(width: 34)
                        .symbolEffect(.bounce, value: isChosen)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.title(for: option)).font(.headline).foregroundStyle(.primary)
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        if let status {
                            Text(status).font(.footnote.weight(.semibold)).foregroundStyle(statusColor)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isChosen ? Color.setupJade : Color.secondary.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quinary, in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(isChosen ? Color.setupJade : .clear, lineWidth: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isChosen ? .isSelected : [])
            .accessibilityIdentifier("setup.listening.\(option.rawValue)")
        }

        private var isChosen: Bool { model.choice == option }

        private func choose() {
            switch option {
            case .onDevice: Task { await model.chooseOnDevice() }
            case .appleSpeech: Task { await model.chooseAppleSpeech() }
            case .cloud: model.chooseCloud()
            case .later: model.chooseLater()
            }
        }

        static func title(for option: SetupGuideModel.Listening) -> String {
            switch option {
            case .onDevice:
                String(
                    localized: "Private, on \(DeviceWords.thisDevice)", bundle: .module,
                    comment: "Setup guide choice: a speech model on this device")
            case .appleSpeech:
                String(localized: "Apple Speech", bundle: .module, comment: "Setup guide choice: Apple's speech engine")
            case .cloud:
                String(localized: "Cloud speech", bundle: .module, comment: "Setup guide choice: cloud speech")
            case .later:
                String(localized: "Decide Later", bundle: .module, comment: "Setup guide choice: skip for now")
            }
        }

        private var symbol: String {
            switch option {
            case .onDevice: "iphone"
            case .appleSpeech: "waveform"
            case .cloud: "cloud.fill"
            case .later: "clock"
            }
        }

        private var detail: String {
            switch option {
            case .onDevice:
                if let row = model.models.suggestedModel, model.suggestedModelState == .installed {
                    String(
                        localized:
                            "\(row.asset.displayName) is on \(DeviceWords.thisDevice). Works offline; your voice never leaves it.",
                        bundle: .module,
                        comment:
                            "Setup guide: the on-device choice once its model is installed; the value is the model name"
                    )
                } else if let row = model.models.suggestedModel {
                    String(
                        localized:
                            "Download \(row.asset.displayName) (\(row.asset.downloadBytes.formatted(.byteCount(style: .file)))). Works offline; your voice never leaves \(DeviceWords.thisDevice).",
                        bundle: .module,
                        comment: "Setup guide: the model download choice; values are the model name and its size")
                } else {
                    ""
                }
            case .appleSpeech:
                String(
                    localized: "No download. iOS asks you to allow Speech Recognition.", bundle: .module,
                    comment: "Setup guide: the Apple Speech choice")
            case .cloud:
                String(
                    localized:
                        "For \(model.cloudSpeech?.languageNames ?? ""). Your voice is sent online to be written. Part of the subscription.",
                    bundle: .module,
                    comment: "Setup guide: the cloud speech choice; the value lists languages, such as Telugu and Hindi"
                )
            case .later:
                String(
                    localized: "Set it up in Settings when you are ready.", bundle: .module,
                    comment: "Setup guide: the decide later choice")
            }
        }

        private var status: String? {
            switch option {
            case .onDevice: onDeviceStatus
            case .appleSpeech:
                switch model.speechRecognition {
                case .granted:
                    String(localized: "Ready", bundle: .module, comment: "Setup guide: a way to listen is ready")
                case .denied, .restricted, .notGranted:
                    String(
                        localized: "Speech Recognition is off. Turn it on in Settings.", bundle: .module,
                        comment: "Setup guide: Speech Recognition was not allowed")
                case .notRequested, nil: nil
                }
            case .cloud: cloudStatus
            case .later: nil
            }
        }

        private var onDeviceStatus: String? {
            switch model.suggestedModelState {
            case .downloading(let received, let total):
                let percent = total > 0 ? Int(Double(received) / Double(total) * 100) : 0
                return String(
                    localized: "Downloading… \(percent)%. You can go on; it finishes in the background.",
                    bundle: .module, comment: "Setup guide: model download progress")
            case .paused:
                return String(localized: "Paused", bundle: .module, comment: "Setup guide: model download paused")
            case .verifying:
                return String(localized: "Checking the download…", bundle: .module, comment: "Setup guide status")
            case .installed:
                return String(localized: "Ready", bundle: .module, comment: "Setup guide: a way to listen is ready")
            case .failed(let error):
                return error.userMessage
            case .notInstalled, nil:
                return model.models.modelError?.userMessage
            }
        }

        private var cloudStatus: String? {
            guard let cloudSpeech = model.cloudSpeech else { return nil }
            if cloudSpeech.status == .turnedOn {
                return String(localized: "Ready", bundle: .module, comment: "Setup guide: a way to listen is ready")
            }
            if let problem = cloudSpeech.problem { return MobileCloudSpeechSection.message(for: problem) }
            if isChosen, let subscription = model.subscription, !subscription.state.grantsAccess {
                return String(
                    localized: "Start the free trial, then choose Cloud speech again.", bundle: .module,
                    comment: "Setup guide: cloud speech needs the subscription first")
            }
            return nil
        }

        private var statusColor: Color {
            switch option {
            case .onDevice where model.suggestedModelState == .installed: .setupJade
            case .appleSpeech where model.speechRecognition == .granted: .setupJade
            case .cloud where model.cloudSpeech?.status == .turnedOn: .setupJade
            default: .secondary
            }
        }
    }

    /// One line of the All set checklist: a check, a progress mark, or a dash, with words that say the same.
    struct ChecklistRow: View {
        let title: String
        let readiness: SetupGuideModel.Readiness

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(color)
                    .symbolEffect(.bounce, value: readiness)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(state).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }

        private var symbol: String {
            switch readiness {
            case .ready: "checkmark.circle.fill"
            case .inProgress: "arrow.down.circle"
            case .notSet: "minus.circle"
            }
        }

        private var color: Color {
            switch readiness {
            case .ready: .setupJade
            case .inProgress: .orange
            case .notSet: .secondary
            }
        }

        private var state: String {
            switch readiness {
            case .ready: String(localized: "Ready", bundle: .module, comment: "Setup guide: a way to listen is ready")
            case .inProgress:
                String(localized: "Downloading", bundle: .module, comment: "Setup guide checklist: still downloading")
            case .notSet:
                String(
                    localized: "Not set up yet. You can do it in Settings.", bundle: .module,
                    comment: "Setup guide checklist")
            }
        }
    }
#endif
