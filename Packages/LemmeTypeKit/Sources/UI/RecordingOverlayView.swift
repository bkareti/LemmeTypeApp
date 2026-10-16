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
                    if coordinator.state == .preparing || coordinator.state == .recording {
                        Text(coordinator.writingMode.displayName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("overlay.mode")
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

    private var message: String? {
        if let failure = coordinator.failure { return failure.userMessage }
        if let issue = coordinator.attention { return issue.userMessage }
        if coordinator.state == .completed { return coordinator.lastDelivery?.announcement }
        return nil
    }

    /// Up to three choices plus Discard, which is always last.
    private var attentionButtons: some View {
        let actions = coordinator.attentionActions
        let primary = Array(actions.filter { $0 != .discard }.prefix(3))
        return HStack {
            ForEach(primary, id: \.identifier) { action in
                Button(action.title(engineName: \.displayName)) { coordinator.perform(action) }
                    .accessibilityIdentifier("overlay.action.\(action.identifier)")
            }
            Spacer(minLength: 0)
            if actions.contains(.discard) {
                Button(DictationAction.discard.title(engineName: \.displayName)) { coordinator.perform(.discard) }
                    .accessibilityIdentifier("overlay.action.discard")
            }
        }
        .controlSize(.small)
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
        case .needsAttention:
            Appearance(
                "exclamationmark.bubble.fill", .orange, String(localized: "Needs your decision", bundle: .module))
        }
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
