import Domain
import SwiftUI

/// Settings › Dictation: writing mode, engine, language, models, and what
/// happens when text can't be inserted (E2-S9).
struct DictationSettingsView: View {
    @Bindable var model: DictationSettingsModel

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

    @ViewBuilder
    private var modelSection: some View {
        let downloadable = model.rows.compactMap { row -> (EngineRow, ModelAsset)? in
            guard case .downloadable(let id) = row.assets, let asset = ModelCatalog.asset(id) else { return nil }
            return (row, asset)
        }
        if !downloadable.isEmpty {
            Section(String(localized: "Downloadable models", bundle: .module)) {
                ForEach(downloadable, id: \.1.id) { row, asset in
                    ModelRow(model: model, row: row, asset: asset)
                }
                if let error = model.modelError {
                    Text(error.userMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("dictation.model.error")
                }
            }
        }
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

/// Download, progress, pause/resume, and removal for one catalog model.
private struct ModelRow: View {
    let model: DictationSettingsModel
    let row: EngineRow
    let asset: ModelAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.displayName)
                    Text(
                        String(
                            localized:
                                "\(asset.downloadBytes.formatted(.byteCount(style: .file))) · \(asset.license) licence · used by \(row.id.displayName)",
                            bundle: .module)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                buttons
            }
            if let fraction = row.model?.fractionCompleted {
                ProgressView(value: fraction)
                    .accessibilityLabel(Text(String(localized: "Download progress", bundle: .module)))
            }
            Text(row.model.map(\.statusTitle) ?? row.availability.statusTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dictation.model.\(asset.id.rawValue).status")
            if case .unsupported(let reason) = row.availability {
                Text(reason.explanation)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch row.model ?? .notInstalled {
        case .notInstalled, .failed:
            Button(String(localized: "Download…", bundle: .module)) {
                Task { await model.offerDownload(of: asset.id) }
            }
            .disabled(isUnsupported)
            .accessibilityIdentifier("dictation.model.\(asset.id.rawValue).download")
        case .downloading:
            Button(String(localized: "Pause", bundle: .module)) { Task { await model.pauseDownload(of: asset.id) } }
                .accessibilityIdentifier("dictation.model.\(asset.id.rawValue).pause")
        case .paused:
            Button(String(localized: "Resume", bundle: .module)) { model.resumeDownload(of: asset.id) }
                .accessibilityIdentifier("dictation.model.\(asset.id.rawValue).resume")
            removeButton
        case .verifying:
            ProgressView().controlSize(.small)
        case .installed:
            Button(String(localized: "Free Memory", bundle: .module)) {
                Task { await model.unloadEngine(using: asset.id) }
            }
            .help(String(localized: "Unloads the model until the next dictation that uses it.", bundle: .module))
            removeButton
        }
    }

    private var removeButton: some View {
        Button(String(localized: "Remove", bundle: .module), role: .destructive) {
            Task { await model.removeModel(asset.id) }
        }
        .accessibilityIdentifier("dictation.model.\(asset.id.rawValue).remove")
    }

    private var isUnsupported: Bool {
        if case .unsupported = row.availability { return true }
        return false
    }
}
