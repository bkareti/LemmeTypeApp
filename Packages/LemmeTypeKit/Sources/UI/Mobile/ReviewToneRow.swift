#if os(iOS)
    import Domain
    import SwiftUI

    /// Neutral, Casual, Professional for English text on the review screen (E12-S5).
    /// A choice is rewritten on this device; nothing goes online.
    struct ReviewToneRow: View {
        let model: QuickDictationModel

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Picker(
                    String(
                        localized: "Tone", bundle: .module, comment: "Label of the tone choices on the review screen"),
                    selection: Binding(
                        get: { model.selectedTone }, set: { if let tone = $0 { model.chooseTone(tone) } })
                ) {
                    ForEach(model.toneChoices, id: \.self) { tone in
                        Text(tone.displayName).tag(Optional(tone))
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.isToneReady)
                .accessibilityIdentifier("quick.tone")
                if let message = model.toneUnavailableMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("quick.tone-unavailable")
                }
            }
            .task { await model.refreshToneAvailability() }
        }
    }
#endif
