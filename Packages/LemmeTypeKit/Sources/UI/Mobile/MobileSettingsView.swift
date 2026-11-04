#if os(iOS)
    import Domain
    import SwiftUI

    /// Settings on iPhone and iPad (E8-S5, E8-S8, E8-S9): language and mode, models,
    /// vocabulary and modes, the copy lifetime, and privacy. Most screens are the
    /// shared ones; this view only arranges them.
    public struct MobileSettingsView: View {
        let dictation: DictationSettingsModel
        let models: ModelsSettingsModel
        let personalization: PersonalizationModel
        let modes: ModesSettingsModel
        let privacy: PrivacyOverviewModel
        let permissions: PermissionsModel
        @AppStorage(CopiedTextLifetime.storageKey) private var lifetimeRaw = CopiedTextLifetime.default.rawValue
        @State private var kind: PersonalizationDraft.Kind = .vocabulary

        public init(
            dictation: DictationSettingsModel, models: ModelsSettingsModel, personalization: PersonalizationModel,
            modes: ModesSettingsModel, privacy: PrivacyOverviewModel, permissions: PermissionsModel
        ) {
            self.dictation = dictation
            self.models = models
            self.personalization = personalization
            self.modes = modes
            self.privacy = privacy
            self.permissions = permissions
        }

        public var body: some View {
            List {
                Section(String(localized: "Dictation", bundle: .module)) {
                    Picker(
                        String(localized: "Language you speak", bundle: .module),
                        selection: Binding(get: { dictation.language }, set: { dictation.setLanguage($0) })
                    ) {
                        ForEach(dictation.languageChoices, id: \.self) { language in
                            Text(DictationSettingsModel.settingLanguageName(language)).tag(language)
                        }
                    }
                    .accessibilityIdentifier("settings.language")
                    if let explanation = dictation.languageStatus?.explanation {
                        Text(explanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.language.status")
                    }
                    if dictation.speechOutputChoices.count > 1 {
                        Picker(
                            String(localized: "Text you get", bundle: .module),
                            selection: Binding(get: { dictation.speechOutput }, set: { dictation.setSpeechOutput($0) })
                        ) {
                            ForEach(dictation.speechOutputChoices, id: \.self) { output in
                                Text(output.displayName).tag(output)
                            }
                        }
                        .accessibilityIdentifier("settings.output")
                    }
                    Text(dictation.readiness.userMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.readiness")
                    Picker(
                        String(localized: "Writing mode", bundle: .module),
                        selection: Binding(get: { modes.currentDefault.id }, set: { modes.setDefault($0) })
                    ) {
                        ForEach(modes.modes) { mode in Text(mode.name).tag(mode.id) }
                    }
                    .accessibilityIdentifier("settings.mode")
                }
                Section(String(localized: "On this device", bundle: .module)) {
                    NavigationLink(String(localized: "Models", bundle: .module)) { ModelsSettingsView(model: models) }
                        .accessibilityIdentifier("settings.models")
                    NavigationLink(String(localized: "Vocabulary and Snippets", bundle: .module)) {
                        VStack(spacing: 0) {
                            PersonalizationSettingsView(model: personalization, kind: $kind)
                            PersonalizationDataControls(personalization: personalization, modes: modes)
                        }
                    }
                    .accessibilityIdentifier("settings.personalization")
                    NavigationLink(String(localized: "Modes", bundle: .module)) { ModesSettingsView(model: modes) }
                        .accessibilityIdentifier("settings.modes")
                }
                Section {
                    Picker(
                        String(localized: "Keep copied text for", bundle: .module),
                        selection: $lifetimeRaw
                    ) {
                        ForEach(CopiedTextLifetime.allCases, id: \.rawValue) { lifetime in
                            Text(Self.name(of: lifetime)).tag(lifetime.rawValue)
                        }
                    }
                    .accessibilityIdentifier("settings.lifetime")
                } header: {
                    Text(String(localized: "Clipboard", bundle: .module))
                } footer: {
                    Text(
                        String(
                            localized:
                                "Copied text stays on this device only (it does not travel to your other devices) and is removed after this time.",
                            bundle: .module))
                }
                Section(String(localized: "Start From a Button", bundle: .module)) {
                    ShortcutGuide()
                }
                Section(String(localized: "Privacy", bundle: .module)) {
                    NavigationLink(String(localized: "Privacy and Data", bundle: .module)) {
                        MobilePrivacyView(model: privacy, permissions: permissions)
                    }
                    .accessibilityIdentifier("settings.privacy")
                }
            }
            .navigationTitle(String(localized: "Settings", bundle: .module))
            .task { await dictation.refresh() }
        }

        static func name(of lifetime: CopiedTextLifetime) -> String {
            let minutes = lifetime.rawValue / 60
            return String(
                localized: "\(minutes) min", bundle: .module,
                comment: "A number of minutes; the unit is abbreviated")
        }
    }

    /// How to start LemmeType from the Action Button or Back Tap (E8-S7). Both run
    /// a Shortcut; neither calls LemmeType directly.
    struct ShortcutGuide: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Action Button", bundle: .module)).font(.headline)
                Text(
                    String(
                        localized:
                            "Settings › Action Button › Shortcut, then choose “Start Dictating” from LemmeType.",
                        bundle: .module))
                Text(String(localized: "Back Tap", bundle: .module)).font(.headline)
                Text(
                    String(
                        localized:
                            "Settings › Accessibility › Touch › Back Tap, then choose a gesture and the “Start Dictating” shortcut.",
                        bundle: .module))
                Text(
                    String(
                        localized:
                            "The app opens and recording starts on screen. Your iPhone must be unlocked. Nothing is recorded in the background.",
                        bundle: .module)
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("settings.shortcut-guide")
        }
    }

    /// What LemmeType keeps on this device, in plain words, with Delete All (E8-S9).
    struct MobilePrivacyView: View {
        let model: PrivacyOverviewModel
        let permissions: PermissionsModel
        @State private var isConfirming = false

        var body: some View {
            List {
                Section {
                    row(
                        "mic", String(localized: "Your voice", bundle: .module),
                        String(
                            localized:
                                "Recorded only while the recording is showing, turned into text on this device, and deleted when the text is ready or you cancel.",
                            bundle: .module))
                    row(
                        "text.alignleft", String(localized: "Your words", bundle: .module),
                        String(
                            localized:
                                "Shown on screen until you copy or discard them. LemmeType keeps no history of what you dictate on iPhone or iPad.",
                            bundle: .module))
                    row(
                        "wifi.slash", String(localized: "The network", bundle: .module),
                        String(
                            localized:
                                "Dictation never uses the network. The only download is a speech model, and only after you confirm it.",
                            bundle: .module))
                    row(
                        "doc.on.clipboard", String(localized: "The clipboard", bundle: .module),
                        String(
                            localized:
                                "Text is copied only when you choose Copy, stays on this device, and expires. LemmeType never pastes or sends for you.",
                            bundle: .module))
                }
                Section(String(localized: "Microphone", bundle: .module)) {
                    let status = permissions.status(for: .microphone)
                    HStack {
                        Text(
                            status.isGranted
                                ? String(localized: "Allowed", bundle: .module)
                                : String(localized: "Not allowed", bundle: .module)
                        )
                        .accessibilityIdentifier("privacy.microphone")
                        Spacer()
                        if !status.isGranted, let action = permissions.action(for: .microphone) {
                            Button(String(localized: "Open Settings", bundle: .module)) {
                                Task { await permissions.perform(action, for: .microphone) }
                            }
                        }
                    }
                }
                Section {
                    Button(String(localized: "Delete All Local Data…", bundle: .module), role: .destructive) {
                        isConfirming = true
                    }
                    .accessibilityIdentifier("privacy.delete-all")
                    if let message = model.resultMessage {
                        Text(message).font(.footnote).accessibilityIdentifier("privacy.result")
                    }
                } footer: {
                    Text(
                        String(
                            localized:
                                "Removes your vocabulary, snippets, modes, and downloaded models from this device.",
                            bundle: .module))
                }
            }
            .navigationTitle(String(localized: "Privacy and Data", bundle: .module))
            .confirmationDialog(
                String(localized: "Delete everything LemmeType keeps on this device?", bundle: .module),
                isPresented: $isConfirming, titleVisibility: .visible
            ) {
                Button(String(localized: "Delete All", bundle: .module), role: .destructive) {
                    model.removesModels = true
                    Task { await model.eraseAll() }
                }
            } message: {
                Text(String(localized: "This can’t be undone.", bundle: .module))
            }
            .onAppear { permissions.refresh() }
        }

        private func row(_ symbol: String, _ title: String, _ text: String) -> some View {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(text).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol).accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
