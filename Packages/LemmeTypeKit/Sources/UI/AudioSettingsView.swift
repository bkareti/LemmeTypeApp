import Domain
import SwiftUI

struct AudioSettingsView: View {
    let model: AudioSettingsModel

    var body: some View {
        Form {
            Section {
                Picker(
                    String(localized: "Microphone", bundle: .module),
                    selection: Binding(get: { model.selection }, set: { model.select($0) })
                ) {
                    Text(String(localized: "System Default", bundle: .module))
                        .tag(AudioInputSelection.systemDefault)
                    ForEach(model.devices) { device in
                        Text(device.name).tag(AudioInputSelection.device(id: device.id))
                    }
                    if model.isSelectedDeviceMissing, case .device(let id) = model.selection {
                        Text(String(localized: "Unavailable microphone", bundle: .module))
                            .tag(AudioInputSelection.device(id: id))
                    }
                }
                .accessibilityIdentifier("audio.input")
                if let notice = model.notice {
                    Text(notice)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("audio.notice")
                }
            }
            Section(String(localized: "Test", bundle: .module)) {
                HStack {
                    Button(
                        model.isTesting
                            ? String(localized: "Stop Test", bundle: .module)
                            : String(localized: "Test Microphone", bundle: .module)
                    ) {
                        Task { model.isTesting ? await model.stopTest() : await model.startTest() }
                    }
                    .accessibilityIdentifier("audio.test")
                    LevelMeter(level: model.level, isActive: model.isTesting)
                }
                Text(String(localized: "Nothing recorded during a test is kept.", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                model.refreshDevices()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onDisappear { Task { await model.stopTest() } }
    }
}

/// Input level bar. Exposes a coarse state to assistive technologies instead
/// of continuously changing numbers.
struct LevelMeter: View {
    let level: Float
    let isActive: Bool

    var body: some View {
        ProgressView(value: Double(level))
            .progressViewStyle(.linear)
            .frame(maxWidth: 200)
            .accessibilityLabel(Text(String(localized: "Input level", bundle: .module)))
            .accessibilityValue(Text(stateDescription))
            .accessibilityIdentifier("audio.level")
    }

    private var stateDescription: String {
        if !isActive { return String(localized: "Off", bundle: .module) }
        return level > 0.1
            ? String(localized: "Sound detected", bundle: .module)
            : String(localized: "No sound", bundle: .module)
    }
}
