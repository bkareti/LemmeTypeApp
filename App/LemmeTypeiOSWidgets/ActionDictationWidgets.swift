import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct ActionDictationWidgets: WidgetBundle {
    var body: some Widget {
        ActionDictationLiveActivity()
    }
}

/// Reached only if iOS runs the Stop intent in the widget, which cannot hold the
/// microphone. The error makes that visible instead of silently doing nothing.
enum ActionDictationBridge {
    struct RanInWidget: LocalizedError {
        var errorDescription: String? { "LemmeType could not stop the dictation here." }
    }

    static func stop() async throws { throw RanInWidget() }
}

private typealias Status = ActionDictationActivityStatus

struct ActionDictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActionDictationAttributes.self) { context in
            let status = shown(context)
            HStack {
                Label(title(status), systemImage: symbol(status))
                Spacer()
                stopButton(status)
            }
            .padding()
        } dynamicIsland: { context in
            let status = shown(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(title(status), systemImage: symbol(status))
                }
                DynamicIslandExpandedRegion(.trailing) { stopButton(status) }
            } compactLeading: {
                statusIcon(status)
            } compactTrailing: {
                compactDetail(status, startedAt: context.state.startedAt)
            } minimal: {
                statusIcon(status)
            }
        }
    }

    /// A stale banner belongs to a run that ended without saying so: it must not claim to be listening.
    private func shown(_ context: ActivityViewContext<ActionDictationAttributes>) -> Status {
        context.isStale ? .ended : context.state.status
    }

    /// A running timer means "recording", so it never shows after Stop.
    @ViewBuilder
    private func compactDetail(_ status: Status, startedAt: Date) -> some View {
        switch status {
        case .listening: Text(startedAt, style: .timer).monospacedDigit().frame(width: 40)
        case .writing: Text("Writing").font(.caption2).foregroundStyle(.secondary)
        case .failed: Text("Failed").font(.caption2).foregroundStyle(.secondary)
        case .ended: Text("Ended").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func title(_ status: Status) -> String {
        switch status {
        case .listening: "Listening"
        case .writing: "Writing your text"
        case .failed: "Dictation didn't work"
        case .ended: "Dictation ended"
        }
    }

    private func symbol(_ status: Status) -> String {
        switch status {
        case .listening: "waveform"
        case .writing: "text.cursor"
        case .failed: "exclamationmark.triangle"
        case .ended: "mic.slash"
        }
    }

    private func statusIcon(_ status: Status) -> some View {
        Image(systemName: symbol(status)).foregroundStyle(status == .listening ? Color.red : Color.secondary)
    }

    @ViewBuilder
    private func stopButton(_ status: Status) -> some View {
        if status == .listening {
            Button(intent: StopActionDictationIntent()) {
                Image(systemName: "stop.fill")
            }
            .tint(.red)
            .accessibilityLabel("Stop")
        }
    }
}
