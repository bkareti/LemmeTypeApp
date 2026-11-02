#if os(iOS)
    import Domain
    import SwiftUI

    /// Quick Dictation on iPhone and iPad (E8-S6): record, stop, cancel, then read
    /// the text and copy it. Nothing is copied until Copy is chosen, and nothing is
    /// ever sent. Recording is always shown on this screen.
    public struct QuickDictationView: View {
        let model: QuickDictationModel
        let dictation: DictationSettingsModel
        let showSettings: () -> Void

        public init(model: QuickDictationModel, dictation: DictationSettingsModel, showSettings: @escaping () -> Void) {
            self.model = model
            self.dictation = dictation
            self.showSettings = showSettings
        }

        public var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    summary
                    switch model.screen {
                    case .ready: ready
                    case .preparing:
                        ProgressView().accessibilityLabel(Text(String(localized: "Preparing", bundle: .module)))
                    case .recording: recording
                    case .processing: processing
                    case .review(let text): review(text)
                    case .attention(let issue): attention(issue)
                    case .failed(let error): failed(error)
                    }
                }
                .frame(maxWidth: 560)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(String(localized: "Dictate", bundle: .module, comment: "Title of the main screen"))
            .alert(
                String(localized: "Allow the microphone?", bundle: .module),
                isPresented: Binding(
                    get: { model.isExplainingMicrophone }, set: { if !$0 { model.cancelExplanation() } })
            ) {
                Button(String(localized: "Continue", bundle: .module)) {
                    Task { await model.continueAfterExplanation() }
                }
                Button(String(localized: "Not Now", bundle: .module), role: .cancel) { model.cancelExplanation() }
            } message: {
                Text(
                    String(
                        localized:
                            "LemmeType listens only while you are on this screen and the recording is showing. Your voice is turned into text on this device and never leaves it.",
                        bundle: .module))
            }
        }

        // MARK: Pieces

        private var summary: some View {
            VStack(spacing: 4) {
                Text(
                    "\(DictationSettingsModel.settingLanguageName(dictation.language)) · \(dictation.speechOutput.displayName)"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("quick.summary")
                if !dictation.readiness.isReady {
                    Button(action: showSettings) {
                        Label(dictation.readiness.userMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                    }
                    .tint(.orange)
                    .accessibilityIdentifier("quick.readiness")
                } else if !dictation.hasReadyEngine {
                    Button(action: showSettings) {
                        Label(
                            String(localized: "No on-device engine is ready. Set one up in Settings.", bundle: .module),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                    }
                    .tint(.orange)
                    .accessibilityIdentifier("quick.no-engine")
                }
            }
        }

        private var ready: some View {
            VStack(spacing: 20) {
                if let lifetime = model.copiedFor {
                    Label(QuickDictationModel.copiedMessage(for: lifetime), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.leading)
                        .accessibilityIdentifier("quick.copied")
                }
                Button(action: model.start) {
                    Label(String(localized: "Start Dictating", bundle: .module), systemImage: "mic.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("quick.record")
                Text(
                    String(
                        localized: "Speak, then read the text. It is copied only when you choose Copy, and never sent.",
                        bundle: .module)
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }

        private var recording: some View {
            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red).accessibilityHidden(true)
                    Text(String(localized: "Recording", bundle: .module)).font(.title2.weight(.semibold))
                    if let started = model.recorder.recordingStartedAt {
                        Text(started, style: .timer).monospacedDigit().font(.title2)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("quick.recording")
                ProgressView(value: Double(min(max(model.recorder.level, 0), 1)))
                    .accessibilityHidden(true)
                Button(action: model.stop) {
                    Label(String(localized: "Stop", bundle: .module), systemImage: "stop.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("quick.stop")
                Button(String(localized: "Cancel", bundle: .module), role: .cancel, action: model.cancel)
                    .accessibilityIdentifier("quick.cancel")
            }
        }

        private var processing: some View {
            VStack(spacing: 12) {
                ProgressView()
                Text(model.recorder.processingPhase?.title ?? String(localized: "Working…", bundle: .module))
                    .accessibilityIdentifier("quick.processing")
                Button(String(localized: "Cancel", bundle: .module), role: .cancel, action: model.cancel)
                    .accessibilityIdentifier("quick.cancel")
            }
        }

        private func review(_ text: String) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                if let title = reviewTitle {
                    Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                }
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("quick.result")
                if model.canCompareWithOriginal {
                    Button(
                        model.showsOriginal
                            ? String(localized: "Show Rewrite", bundle: .module)
                            : String(localized: "Show Original", bundle: .module), action: model.toggleOriginal
                    )
                    .accessibilityIdentifier("quick.compare")
                }
                Button {
                    Task { await model.copy() }
                } label: {
                    Label(String(localized: "Copy", bundle: .module), systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("quick.copy")
                HStack {
                    if let retry = model.reviewRetryAction {
                        Button(retry.title(engineName: { $0.displayName })) { model.perform(retry) }
                            .accessibilityIdentifier("quick.action.\(retry.identifier)")
                    }
                    Button(String(localized: "Dictate Again", bundle: .module), action: model.dictateAgain)
                        .accessibilityIdentifier("quick.again")
                    Spacer()
                    Button(String(localized: "Discard", bundle: .module), role: .destructive, action: model.discard)
                        .accessibilityIdentifier("quick.discard")
                }
                Text(reviewFootnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        private var reviewTitle: String? {
            switch model.reviewKind {
            case .translation: String(localized: "Translation", bundle: .module)
            case .rewrite: String(localized: "Rewritten Text", bundle: .module)
            case .dictation, nil: nil
            }
        }

        private var reviewFootnote: String {
            switch model.reviewKind {
            case .translation:
                String(
                    localized: "Read the translation. It is copied only when you choose Copy, and never sent.",
                    bundle: .module)
            case .rewrite:
                String(
                    localized: "Read the rewrite. It is copied only when you choose Copy, and never sent.",
                    bundle: .module)
            case .dictation, nil: DictationIssue.reviewText.userMessage
            }
        }

        private func attention(_ issue: DictationIssue) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Label(issue.userMessage, systemImage: "exclamationmark.triangle.fill")
                    .accessibilityIdentifier("quick.attention")
                ForEach(model.recorder.attentionActions, id: \.identifier) { action in
                    Button(action.title(engineName: { $0.displayName })) { model.perform(action) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("quick.action.\(action.identifier)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func failed(_ error: AudioCaptureError) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                    .accessibilityIdentifier("quick.failed")
                if error == .microphonePermissionMissing {
                    Button(String(localized: "Open Settings", bundle: .module), action: model.openSystemSettings)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("quick.open-settings")
                }
                Button(String(localized: "Try Again", bundle: .module), action: model.recorder.dismiss)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("quick.try-again")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
