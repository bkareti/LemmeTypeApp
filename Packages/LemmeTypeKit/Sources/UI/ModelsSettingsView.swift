import Domain
import SwiftUI

/// Settings › Dictation › Models (E5-S2).
struct ModelsSettingsView: View {
    @Bindable var model: ModelsSettingsModel

    var body: some View {
        Form {
            Section {
                Picker(
                    String(localized: "Whisper model", bundle: .module),
                    selection: Binding(get: { model.whisperModel }, set: { model.setWhisperModel($0) })
                ) {
                    Text(String(localized: "Automatic (best installed for the performance profile)", bundle: .module))
                        .tag(WhisperModelChoice.automatic)
                    ForEach(model.whisperRows) { row in
                        Text(row.asset.displayName).tag(WhisperModelChoice.specific(row.id))
                    }
                }
                .accessibilityIdentifier("models.whisper")
                Text(
                    String(
                        localized:
                            "Models run only on this Mac. A model is checked against its published fingerprint before it’s first used after each launch; a modified file is deleted.",
                        bundle: .module)
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            performanceSection
            Section(String(localized: "Models", bundle: .module)) {
                ForEach(model.rows) { row in
                    ModelCatalogRow(model: model, row: row)
                }
                if let error = model.modelError {
                    Text(error.userMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("models.error")
                }
                LabeledContent(String(localized: "Disk used by models", bundle: .module)) {
                    Text(model.usedBytes.formatted(.byteCount(style: .file)))
                }
                LabeledContent(String(localized: "Free space", bundle: .module)) {
                    Text(model.availableBytes.formatted(.byteCount(style: .file)))
                }
            }
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
            Text(
                offer.confirmationMessage + "\n\n"
                    + offer.asset.fitMessage(model.rows.first { $0.id == offer.asset.id }?.fit))
        }
    }
}

extension ModelsSettingsView {
    @ViewBuilder
    var performanceSection: some View {
        Section(String(localized: "Performance", bundle: .module)) {
            Picker(
                String(localized: "Profile", bundle: .module),
                selection: Binding(get: { model.profile }, set: { model.setProfile($0) })
            ) {
                ForEach(PerformanceProfile.allCases, id: \.self) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .accessibilityIdentifier("models.profile")
            Text(model.profile.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let reduction = model.plan.reduction {
                Label(reduction.message, systemImage: reduction == .thermal ? "thermometer.high" : "battery.25")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("models.reduced")
            } else if model.profile == .automatic {
                Text(String(localized: "In effect now: \(model.plan.profile.title).", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Picker(
                String(localized: "Unload models after", bundle: .module),
                selection: Binding(get: { model.idleUnload }, set: { model.setIdleUnload($0) })
            ) {
                ForEach(IdleUnloadPolicy.choices, id: \.self) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .accessibilityIdentifier("models.idleUnload")
            Text(
                String(
                    localized:
                        "Models load when you dictate and are removed from memory after this much time without dictation, or at once when your Mac runs short of memory.",
                    bundle: .module)
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

extension PerformanceProfile {
    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic", bundle: .module)
        case .balanced: String(localized: "Balanced", bundle: .module)
        case .lowPower: String(localized: "Low Power", bundle: .module)
        case .bestAccuracy: String(localized: "Best Accuracy", bundle: .module)
        }
    }

    var summary: String {
        switch self {
        case .automatic:
            String(localized: "Balanced, or Low Power while your Mac is in Low Power Mode.", bundle: .module)
        case .balanced:
            String(
                localized: "Prefers Whisper Base, uses the GPU, and starts loading the model while you speak.",
                bundle: .module)
        case .lowPower:
            String(
                localized:
                    "Prefers Whisper Tiny, uses two CPU cores and no GPU, loads only when needed, and frees memory after a minute.",
                bundle: .module)
        case .bestAccuracy:
            String(
                localized: "Prefers Whisper Small when installed, uses the GPU, and loads while you speak.",
                bundle: .module)
        }
    }
}

extension PerformancePlan.Reduction {
    var message: String {
        switch self {
        case .lowPowerMode: String(localized: "Using Low Power because Low Power Mode is on.", bundle: .module)
        case .thermal:
            String(localized: "Performance is reduced to keep your Mac cool.", bundle: .module)
        }
    }
}

extension IdleUnloadPolicy {
    var title: String {
        switch self {
        case .after(let minutes) where minutes == 1: String(localized: "1 minute", bundle: .module)
        case .after(let minutes) where minutes == 60: String(localized: "1 hour", bundle: .module)
        case .after(let minutes): String(localized: "\(minutes) minutes", bundle: .module)
        case .never: String(localized: "Never", bundle: .module)
        }
    }
}

/// One model: what it costs, whether it suits this Mac, and its state.
private struct ModelCatalogRow: View {
    let model: ModelsSettingsModel
    let row: ModelsSettingsModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.asset.displayName)
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                buttons
            }
            if let fraction = row.state.fractionCompleted {
                ProgressView(value: fraction)
                    .accessibilityLabel(
                        Text(String(localized: "Download progress for \(row.asset.displayName)", bundle: .module)))
            }
            HStack {
                Text(row.state.statusTitle)
                    .accessibilityIdentifier("models.\(row.id.rawValue).status")
                Text("·")
                Text(row.fit.title)
                    .foregroundStyle(row.fit.canRun ? Color.secondary : Color.orange)
                    .accessibilityIdentifier("models.\(row.id.rawValue).fit")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var details: String {
        let asset = row.asset
        let download = asset.downloadBytes.formatted(.byteCount(style: .file))
        let memory = Int64(asset.runtimeMemoryBytes).formatted(.byteCount(style: .memory))
        let languages = asset.languages.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
            .formatted(.list(type: .and))
        let minimum = Int64(asset.hardware.minimumMemoryBytes).formatted(.byteCount(style: .memory))
        return String(
            localized:
                "\(asset.tier.title) · \(download) download and disk · about \(memory) memory · \(languages) · Apple silicon, \(minimum)+ memory",
            bundle: .module)
    }

    @ViewBuilder
    private var buttons: some View {
        let id = row.id.rawValue
        switch row.state {
        case .notInstalled, .failed:
            Button(String(localized: "Download…", bundle: .module)) {
                Task { await model.offerDownload(of: row.id) }
            }
            .disabled(!row.fit.canRun)
            .accessibilityIdentifier("models.\(id).download")
            .accessibilityLabel(Text(String(localized: "Download \(row.asset.displayName)", bundle: .module)))
        case .downloading:
            Button(String(localized: "Pause", bundle: .module)) { Task { await model.pauseDownload(of: row.id) } }
                .accessibilityIdentifier("models.\(id).pause")
        case .paused:
            Button(String(localized: "Resume", bundle: .module)) { model.resumeDownload(of: row.id) }
                .accessibilityIdentifier("models.\(id).resume")
            removeButton
        case .verifying:
            ProgressView().controlSize(.small)
        case .installed:
            removeButton
        }
    }

    private var removeButton: some View {
        Button(String(localized: "Remove", bundle: .module), role: .destructive) {
            Task { await model.removeModel(row.id) }
        }
        .accessibilityIdentifier("models.\(row.id.rawValue).remove")
        .accessibilityLabel(Text(String(localized: "Remove \(row.asset.displayName)", bundle: .module)))
    }
}

extension ModelTier {
    var title: String {
        switch self {
        case .fastest: String(localized: "Fastest", bundle: .module)
        case .balanced: String(localized: "Balanced", bundle: .module)
        case .mostAccurate: String(localized: "Most accurate", bundle: .module)
        }
    }
}

extension ModelFit {
    var title: String {
        switch self {
        case .recommended: String(localized: "Recommended for this Mac", bundle: .module)
        case .supported: String(localized: "Runs on this Mac; more memory recommended", bundle: .module)
        case .unsupported(let reason): reason.explanation
        }
    }
}

extension ModelAsset {
    func fitMessage(_ fit: ModelFit?) -> String {
        let recommended = Int64(hardware.recommendedMemoryBytes).formatted(.byteCount(style: .memory))
        switch fit {
        case .supported:
            return String(
                localized: "This Mac runs it, but \(recommended) of memory is recommended for this model.",
                bundle: .module)
        default:
            return fit?.title ?? ""
        }
    }
}
