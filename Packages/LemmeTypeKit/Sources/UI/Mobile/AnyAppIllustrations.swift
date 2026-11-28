#if os(iOS)
    import SwiftUI

    // MARK: Dictate in any app

    /// A phone outline, shared by the Action Button and Back Tap pictures.
    struct PhoneOutline<Screen: View>: View {
        @ViewBuilder let screen: () -> Screen

        var body: some View {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.secondary, lineWidth: 3)
                .frame(width: 84, height: 156)
                .overlay { screen() }
        }
    }

    /// A keyboard whose globe key is pressed, then turns into the LemmeType keyboard with a microphone key.
    struct KeyboardIllustration: View {
        enum Phase: CaseIterable { case typing, globe, switched }

        var body: some View {
            LoopingIllustration(phases: Phase.allCases, still: .switched) { phase in
                switch phase {
                case .typing: .easeInOut(duration: 0.4).delay(1.2)
                case .globe: .spring(duration: 0.3, bounce: 0.4).delay(0.6)
                case .switched: .spring(duration: 0.5, bounce: 0.3)
                }
            } content: { phase in
                let switched = phase == .switched
                VStack(spacing: 6) {
                    ForEach([10, 9, 7], id: \.self) { count in
                        HStack(spacing: 4) {
                            ForEach(0..<count, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(switched ? Color.setupJade.opacity(0.28) : Color.secondary.opacity(0.3))
                                    .frame(width: 16, height: 20)
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(phase == .globe ? Color.setupJade : Color.secondary.opacity(0.3))
                            .frame(width: 26, height: 22)
                            .overlay {
                                Image(systemName: "globe").font(.caption.weight(.bold))
                                    .foregroundStyle(phase == .globe ? .white : .primary)
                            }
                            .scaleEffect(phase == .globe ? 0.86 : 1)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(switched ? Color.setupJade : Color.secondary.opacity(0.3))
                            .frame(width: 110, height: 22)
                            .overlay {
                                Image(systemName: "mic.fill").font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .opacity(switched ? 1 : 0)
                                    .scaleEffect(switched ? 1 : 0.3)
                            }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 40, height: 22)
                    }
                }
                .padding(12)
                .background(.background.secondary, in: .rect(cornerRadius: 14))
            }
        }
    }

    /// A finger presses the side button, the phone records, a second press writes the text.
    struct ActionButtonIllustration: View {
        enum Phase: CaseIterable { case idle, press, recording, pressAgain, written }

        var body: some View {
            LoopingIllustration(phases: Phase.allCases, still: .recording) { phase in
                switch phase {
                case .idle: .easeInOut(duration: 0.4).delay(1.0)
                case .press, .pressAgain: .spring(duration: 0.25, bounce: 0.3).delay(0.3)
                case .recording: .easeOut(duration: 0.4).delay(0.2)
                case .written: .easeOut(duration: 0.5).delay(0.2)
                }
            } content: { phase in
                let pressed = phase == .press || phase == .pressAgain
                HStack(spacing: 2) {
                    Image(systemName: "hand.point.right.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                        .offset(x: pressed ? 4 : -6, y: -38)
                    ZStack(alignment: .topLeading) {
                        PhoneOutline {
                            VStack(spacing: 8) {
                                if phase == .recording || phase == .pressAgain {
                                    Image(systemName: "waveform")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.red)
                                        .transition(.scale.combined(with: .opacity))
                                }
                                if phase == .written {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Capsule().fill(Color.setupJade).frame(width: 50, height: 7)
                                        Capsule().fill(Color.setupJade).frame(width: 34, height: 7)
                                    }
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                        // The Action Button on the upper left edge.
                        Capsule()
                            .fill(pressed ? Color.setupJade : Color.secondary)
                            .frame(width: 5, height: 20)
                            .offset(x: pressed ? -1 : -4, y: 30)
                    }
                }
                .frame(width: 150, height: 170)
            }
        }
    }

    /// Two taps on the back of the phone, each with a ripple, then a microphone appears.
    struct BackTapIllustration: View {
        enum Phase: CaseIterable { case idle, tap, lift, tapAgain, recording }

        var body: some View {
            LoopingIllustration(phases: Phase.allCases, still: .recording) { phase in
                switch phase {
                case .idle: .easeInOut(duration: 0.4).delay(1.0)
                case .tap, .tapAgain: .easeOut(duration: 0.18)
                case .lift: .easeOut(duration: 0.18)
                case .recording: .spring(duration: 0.5, bounce: 0.4).delay(0.1)
                }
            } content: { phase in
                let tapping = phase == .tap || phase == .tapAgain
                ZStack {
                    PhoneOutline {
                        ZStack(alignment: .topLeading) {
                            // The camera bump on the back.
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(.secondary, lineWidth: 2)
                                .frame(width: 34, height: 34)
                                .padding(10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            Circle()
                                .stroke(Color.setupJade, lineWidth: 3)
                                .frame(width: 40, height: 40)
                                .scaleEffect(tapping ? 1.4 : 0.6)
                                .opacity(tapping ? 0.9 : 0)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.orange)
                        .offset(x: 18, y: tapping ? 24 : 34)
                        .opacity(phase == .recording ? 0 : 1)
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white, Color.setupJade)
                        .scaleEffect(phase == .recording ? 1 : 0.2)
                        .opacity(phase == .recording ? 1 : 0)
                        .offset(y: 4)
                }
                .frame(width: 150, height: 170)
            }
        }
    }
#endif
