import Domain
import SwiftUI

/// The floating recorder status. Each state has its own icon, colour, and
/// words, so nothing depends on animation; the level bar is decorative and
/// hidden from VoiceOver (state changes are announced instead).
struct RecordingOverlayView: View {
    let coordinator: RecordingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: appearance.symbol)
                    .foregroundStyle(appearance.color)
                    .symbolEffect(.pulse, isActive: coordinator.state == .recording && !reduceMotion)
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appearance.title)
                        .font(.headline)
                        .accessibilityIdentifier("overlay.state")
                    if coordinator.state.isCapturing || coordinator.state == .processing {
                        Text(modeLine)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("overlay.mode")
                        if let context = coordinator.activeContext?.statusText {
                            Label(context, systemImage: "text.cursor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("overlay.context")
                        }
                    }
                    if let startedAt = coordinator.recordingStartedAt, coordinator.state == .recording {
                        TimelineView(.periodic(from: startedAt, by: 1)) { context in
                            Text(
                                Duration.seconds(context.date.timeIntervalSince(startedAt)).formatted(
                                    .time(pattern: .minuteSecond))
                            )
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text(String(localized: "Recording time", bundle: .module)))
                        }
                    }
                }
                Spacer(minLength: 12)
                buttons
            }
            if coordinator.state == .recording {
                ProgressView(value: Double(coordinator.level))
                    .progressViewStyle(.linear)
                    .tint(.red)
                    .accessibilityHidden(true)
            }
            if coordinator.state == .processing, let progress = coordinator.processingProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .accessibilityHidden(true)
            }
            if let message {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("overlay.message")
            }
            if let style = coordinator.reviewStyle?.summary, !style.isEmpty {
                Label(style, systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("overlay.review.style")
            }
            if let review = coordinator.reviewText {
                let original = coordinator.reviewOriginal
                let showsOriginal = coordinator.reviewShowsOriginal
                Text(showsOriginal ? (original ?? review) : review)
                    .font(.body)
                    .lineLimit(8)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(Text(reviewLabel(showingOriginal: showsOriginal && original != nil)))
                    .accessibilityValue(Text(showsOriginal ? (original ?? review) : review))
                    .accessibilityIdentifier("overlay.review.text")
                if original != nil {
                    Button(
                        showsOriginal
                            ? String(localized: "Show rewrite", bundle: .module)
                            : String(localized: "Show original", bundle: .module)
                    ) { coordinator.toggleReviewOriginal() }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .accessibilityIdentifier("overlay.review.toggle")
                }
            }
            if coordinator.attention != nil {
                attentionButtons
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(appearance.color.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(localized: "LemmeType recorder", bundle: .module)))
    }

    @ViewBuilder
    private var buttons: some View {
        switch coordinator.state {
        case .preparing, .recording:
            Button(String(localized: "Stop", bundle: .module)) { coordinator.requestStop() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("overlay.stop")
            Button(String(localized: "Cancel", bundle: .module)) { coordinator.requestCancel() }
                .accessibilityIdentifier("overlay.cancel")
        case .failed:
            if let action = coordinator.recoveryAction {
                Button(action.title) { coordinator.perform(action) }
                    .accessibilityIdentifier("overlay.action")
            }
            Button(String(localized: "Dismiss", bundle: .module)) { coordinator.dismiss() }
                .accessibilityIdentifier("overlay.dismiss")
        case .processing:
            Button(String(localized: "Cancel", bundle: .module)) { coordinator.requestCancel() }
                .accessibilityIdentifier("overlay.cancel")
        case .idle, .stopping, .completed, .cancelled, .needsAttention:
            EmptyView()
        }
    }

    private var modeLine: String {
        if coordinator.activePurpose == .editing {
            return String(localized: "Editing selection · On this Mac", bundle: .module)
        }
        var mode = coordinator.activeDictationMode?.displayName ?? coordinator.writingMode.displayName
        // The choices that change the text are always visible while it is processed (E9-S3, E10-S4).
        if let settings = coordinator.activeSettings,
            LanguageReadiness.isBeyondEnglishDictation(
                language: settings.language, output: settings.speechOutput)
        {
            let spoken = DictationSettingsModel.settingLanguageName(settings.language)
            let route =
                settings.speechOutput == .english && !SpokenLanguages.isEnglish(settings.language)
                ? "\(spoken) → English" : spoken
            mode += " · \(route)"
        }
        if let style = coordinator.activeDictationMode?.effectiveStyle.summary, !style.isEmpty {
            mode += " · \(style)"
        }
        if coordinator.activeModeSource == .appRule {
            return String(localized: "\(mode) for this app · On this Mac", bundle: .module)
        }
        return String(localized: "\(mode) · On this Mac", bundle: .module)
    }

    private var message: String? {
        if let failure = coordinator.failure { return failure.userMessage }
        if let issue = coordinator.attention { return issue.userMessage }
        if coordinator.state == .completed { return coordinator.lastDelivery?.announcement }
        return nil
    }

    /// Choices in rows of three, with Discard always last on its own side.
    private var attentionButtons: some View {
        let actions = coordinator.attentionActions
        let rows = Array(actions.filter { $0 != .discard }).chunked(into: 3)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    ForEach(row, id: \.identifier) { action in
                        Button(title(of: action)) { coordinator.perform(action) }
                            .accessibilityIdentifier("overlay.action.\(action.identifier)")
                    }
                    Spacer(minLength: 0)
                    if index == rows.count - 1, actions.contains(.discard) {
                        discardButton
                    }
                }
            }
            if rows.isEmpty, actions.contains(.discard) {
                HStack {
                    Spacer(minLength: 0)
                    discardButton
                }
            }
        }
        .controlSize(.small)
    }

    private var discardButton: some View {
        Button(DictationAction.discard.title(engineName: \.displayName)) { coordinator.perform(.discard) }
            .accessibilityIdentifier("overlay.action.discard")
    }

    private func reviewLabel(showingOriginal: Bool) -> String {
        if showingOriginal { return String(localized: "Original text", bundle: .module) }
        return coordinator.attention == .reviewTranslation
            ? String(localized: "Translation", bundle: .module) : String(localized: "Rewritten text", bundle: .module)
    }

    /// Retry reads "Translate Again" while a translation is being reviewed.
    private func title(of action: DictationAction) -> String {
        if action == .retry, coordinator.attention == .reviewTranslation {
            return String(localized: "Translate Again", bundle: .module)
        }
        return action.title(engineName: \.displayName)
    }

    private var appearance: Appearance {
        switch coordinator.state {
        case .idle, .preparing:
            Appearance("mic.circle", .orange, String(localized: "Starting microphone…", bundle: .module))
        case .recording:
            Appearance("record.circle.fill", .red, String(localized: "Recording", bundle: .module))
        case .stopping:
            Appearance("stop.circle", .orange, String(localized: "Finishing…", bundle: .module))
        case .processing:
            Appearance(
                "hourglass", .blue,
                coordinator.processingPhase?.title ?? String(localized: "Processing…", bundle: .module))
        case .completed:
            Appearance("checkmark.circle.fill", .green, String(localized: "Done", bundle: .module))
        case .cancelled:
            Appearance("xmark.circle", .secondary, String(localized: "Cancelled", bundle: .module))
        case .failed:
            Appearance("exclamationmark.triangle.fill", .yellow, String(localized: "Couldn’t record", bundle: .module))
        case .needsAttention(.reviewTranslation):
            Appearance("text.bubble.fill", .blue, String(localized: "Review translation", bundle: .module))
        case .needsAttention(.reviewRewrite(nil)):
            Appearance("wand.and.stars", .blue, String(localized: "Review rewrite", bundle: .module))
        case .needsAttention(.reviewRewrite):
            Appearance("text.badge.xmark", .orange, String(localized: "Not rewritten", bundle: .module))
        case .needsAttention:
            Appearance(
                "exclamationmark.bubble.fill", .orange, String(localized: "Needs your decision", bundle: .module))
        }
    }
}

extension Array {
    fileprivate func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

private struct Appearance {
    let symbol: String
    let color: Color
    let title: String

    init(_ symbol: String, _ color: Color, _ title: String) {
        self.symbol = symbol
        self.color = color
        self.title = title
    }
}

extension RecordingCoordinator.RecoveryAction {
    var title: String {
        switch self {
        case .openPermissions: String(localized: "Open Permissions", bundle: .module)
        case .openAudioSettings: String(localized: "Audio Settings", bundle: .module)
        case .tryAgain: String(localized: "Try Again", bundle: .module)
        }
    }
}
