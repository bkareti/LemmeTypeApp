import Domain
import SwiftUI

/// Settings › Dictation: writing mode, engine, language, models, and what
/// happens when text can't be inserted (E2-S9).
struct DictationSettingsView: View {
    @Bindable var model: DictationSettingsModel
    /// Opens Settings › Dictation › Models, which manages downloads (E5-S2).
    var showModels: () -> Void = {}

    var body: some View {
        Form {
            writingSection
            engineSection
            modelSection
            deliverySection
        }
        .formStyle(.grouped)
        .task { await model.refresh() }
        .alert(
            String(localized: "Download \(model.downloadOffer?.asset.displayName ?? "")?", bundle: .module),
            isPresented: Binding(get: { model.downloadOffer != nil }, set: { if !$0 { model.downloadOffer = nil } }),
            presenting: model.downloadOffer
        ) { offer in
            Button(String(localized: "Download", bundle: .module)) { model.confirmDownload() }
                .disabled(!offer.hasEnoughSpace)
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { model.downloadOffer = nil }
        } message: { offer in
            Text(offer.confirmationMessage)
        }
    }

    // MARK: Writing

    private var writingSection: some View {
        Section(String(localized: "Writing", bundle: .module)) {
            Picker(
                String(localized: "Writing mode", bundle: .module),
                selection: Binding(get: { model.writingMode }, set: { model.setWritingMode($0) })
            ) {
                ForEach(WritingMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName)
                        Text(mode.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tag(mode)
                    .accessibilityIdentifier("dictation.mode.\(mode.rawValue)")
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("dictation.mode")
        }
    }

    // MARK: Engine

    private var engineSection: some View {
        Section {
            Picker(
                String(localized: "Recognition engine", bundle: .module),
                selection: Binding(get: { model.selectedEngine }, set: { model.selectEngine($0) })
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Automatic", bundle: .module))
                    Text(model.automaticExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dictation.engine.automatic.explanation")
                }
                .tag(RecognitionEngineID?.none)
                ForEach(model.rows) { row in
                    EngineRowLabel(row: row).tag(Optional(row.id))
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("dictation.engine")

            if let blocked = model.blockedEngine {
                BlockedEngineNotice(model: model, engine: blocked.id, availability: blocked.availability)
            } else if !model.hasReadyEngine {
                Text(String(localized: "No on-device engine is ready. Set one up below.", bundle: .module))
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("dictation.engine.none-ready")
            }

            Toggle(
                String(
                    localized: "If my engine isn’t ready, use another on-device engine without asking", bundle: .module),
                isOn: Binding(get: { model.fallsBackToReadyEngine }, set: { model.setFallsBackToReadyEngine($0) })
            )
            .accessibilityIdentifier("dictation.engine.fallback")

            Picker(
                String(localized: "Language", bundle: .module),
                selection: Binding(get: { model.language }, set: { model.setLanguage($0) })
            ) {
                ForEach(model.languages, id: \.self) { language in
                    Text(DictationSettingsModel.languageName(language)).tag(language)
                }
            }
            .accessibilityIdentifier("dictation.language")
        } header: {
            Text(String(localized: "Recognition", bundle: .module))
        } footer: {
            Text(
                String(
                    localized:
                        "Every engine runs on this Mac. Your recordings and text never leave it. Changes apply to your next dictation.",
                    bundle: .module)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Models

    private var modelSection: some View {
        Section(String(localized: "Downloadable models", bundle: .module)) {
            HStack {
                Text(modelSummary)
                    .accessibilityIdentifier("dictation.model.summary")
                Spacer()
                Button(String(localized: "Manage Models…", bundle: .module), action: showModels)
                    .accessibilityIdentifier("dictation.models.manage")
            }
        }
    }

    private var modelSummary: String {
        let missing = model.rows.filter { row in
            if case .downloadable = row.assets { return !row.isReady }
            return false
        }
        return missing.isEmpty
            ? String(localized: "Whisper models are downloaded and verified in Models.", bundle: .module)
            : String(localized: "Whisper needs a model download. Choose one in Models.", bundle: .module)
    }

    // MARK: Delivery

    private var deliverySection: some View {
        Section {
            Picker(
                String(localized: "When text can’t be inserted directly", bundle: .module),
                selection: Binding(
                    get: { model.clipboardFallback.fallback }, set: { model.setClipboardFallback($0) })
            ) {
                ForEach(ClipboardFallback.allCases, id: \.self) { fallback in
                    Text(fallback.title).tag(fallback)
                }
            }
            .accessibilityIdentifier("dictation.fallback")
            if model.clipboardFallback.fallback == .pasteAndRestore {
                Picker(
                    String(localized: "Restore clipboard after", bundle: .module),
                    selection: Binding(
                        get: { model.clipboardFallback.restoreDelay }, set: { model.setRestoreDelay($0) })
                ) {
                    ForEach(ClipboardFallbackPolicy.restoreDelayChoices, id: \.self) { seconds in
                        Text(Duration.seconds(seconds).formatted(.units(allowed: [.seconds, .milliseconds])))
                            .tag(seconds)
                    }
                }
                .accessibilityIdentifier("dictation.restoreDelay")
            }
        } header: {
            Text(String(localized: "Inserting text", bundle: .module))
        } footer: {
            Text(model.clipboardFallback.fallback.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private typealias EngineRow = DictationSettingsModel.EngineRow

/// Name, readiness, location, languages, and download requirement.
private struct EngineRowLabel: View {
    let row: EngineRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(row.id.displayName)
                Text(row.availability.statusTitle)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(row.isReady ? Color.green.opacity(0.2) : Color.orange.opacity(0.2), in: Capsule())
                    .accessibilityIdentifier("dictation.engine.\(row.id.rawValue).status")
            }
            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dictation.engine.\(row.id.rawValue).detail")
        }
        .accessibilityElement(children: .combine)
    }
}

/// Explains why the selected engine can't run and offers the fix.
private struct BlockedEngineNotice: View {
    let model: DictationSettingsModel
    let engine: RecognitionEngineID
    let availability: EngineAvailability

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                String(
                    localized:
                        "\(engine.displayName) isn’t ready: \(availability.statusTitle). LemmeType will ask before using another engine.",
                    bundle: .module)
            )
            .foregroundStyle(.orange)
            .accessibilityIdentifier("dictation.engine.blocked")
            HStack {
                if availability == .permissionUnavailable, model.canRequestSpeechRecognition {
                    Button(String(localized: "Allow Speech Recognition", bundle: .module)) {
                        Task { await model.allowSpeechRecognition() }
                    }
                }
                Button(String(localized: "Use Automatic", bundle: .module)) { model.selectEngine(nil) }
            }
        }
    }
}
