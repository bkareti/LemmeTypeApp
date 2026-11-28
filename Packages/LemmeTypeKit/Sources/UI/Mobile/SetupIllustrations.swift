#if os(iOS)
    import Domain
    import SwiftUI

    // The setup guide's pictures (E8-S10). Each is drawn with SwiftUI shapes and SF Symbols, loops only while
    // it is on screen, and is a still picture when Reduce Motion is on. All are hidden from VoiceOver: the
    // text next to each one says everything it shows.

    extension Color {
        /// The jade of the app icon (`#03A58D`, `scripts/make-app-icons.py`).
        static let setupJade = Color(red: 3 / 255, green: 165 / 255, blue: 141 / 255)
    }

    /// Plays `phases` in a loop, or shows `still` when Reduce Motion is on.
    struct LoopingIllustration<Phase: Equatable, Content: View>: View {
        let phases: [Phase]
        let still: Phase
        let animation: (Phase) -> Animation?
        @ViewBuilder let content: (Phase) -> Content
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Group {
                if reduceMotion {
                    content(still)
                } else {
                    PhaseAnimator(phases, content: content, animation: animation)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: Welcome

    /// Sound bars, then lines of text appearing: speak, and it is written.
    struct WelcomeIllustration: View {
        enum Phase: CaseIterable { case quiet, speaking, writing, written }

        private static let speaking: [CGFloat] = [20, 44, 30, 56, 36, 48, 18]
        private static let writing: [CGFloat] = [12, 22, 16, 28, 18, 24, 10]

        var body: some View {
            LoopingIllustration(phases: Phase.allCases, still: .written) { phase in
                switch phase {
                case .quiet: .easeInOut(duration: 0.6).delay(1.2)
                case .speaking: .spring(duration: 0.5, bounce: 0.5)
                case .writing: .easeOut(duration: 0.8)
                case .written: .easeOut(duration: 0.7)
                }
            } content: { phase in
                VStack(spacing: 22) {
                    HStack(alignment: .center, spacing: 6) {
                        ForEach(0..<7, id: \.self) { index in
                            Capsule()
                                .fill(Color.setupJade.gradient)
                                .frame(width: 9, height: barHeight(index, phase))
                        }
                    }
                    .frame(height: 60)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(0..<3, id: \.self) { line in
                            Capsule()
                                .fill(.secondary.opacity(0.35))
                                .frame(width: lineWidth(line, phase), height: 10)
                        }
                    }
                    .frame(width: 210, alignment: .leading)
                }
                .padding(28)
                .background(.background.secondary, in: .rect(cornerRadius: 28))
            }
        }

        private func barHeight(_ index: Int, _ phase: Phase) -> CGFloat {
            switch phase {
            case .quiet, .written: 8
            case .speaking: Self.speaking[index]
            case .writing: Self.writing[index]
            }
        }

        private func lineWidth(_ line: Int, _ phase: Phase) -> CGFloat {
            switch phase {
            case .quiet, .speaking: [24, 0, 0][line]
            case .writing: [210, 120, 0][line]
            case .written: [210, 170, 110][line]
            }
        }
    }

    // MARK: Microphone

    /// A microphone sending out rings; a check once allowed, a crossed-out microphone when off.
    struct MicrophoneIllustration: View {
        let status: PermissionStatus

        enum Phase: CaseIterable { case rest, ring }

        var body: some View {
            LoopingIllustration(phases: isAsking ? Phase.allCases : [.rest], still: .rest) { phase in
                phase == .ring ? .easeOut(duration: 1.4) : nil
            } content: { phase in
                ZStack {
                    if isAsking {
                        ForEach(0..<3, id: \.self) { ring in
                            Circle()
                                .stroke(Color.setupJade, lineWidth: 2)
                                .frame(width: 104, height: 104)
                                .scaleEffect(phase == .ring ? 1 + 0.32 * CGFloat(ring + 1) : 1)
                                .opacity(phase == .ring ? 0 : 0.55 - 0.15 * Double(ring))
                        }
                    }
                    Circle()
                        .fill(fill.gradient)
                        .frame(width: 104, height: 104)
                        .shadow(color: fill.opacity(0.35), radius: 12, y: 6)
                    Image(systemName: symbol)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: status)
                }
                .frame(width: 220, height: 220)
            }
        }

        private var isAsking: Bool { status == .notRequested }

        private var symbol: String {
            switch status {
            case .granted: "checkmark"
            case .notRequested: "mic.fill"
            case .denied, .restricted, .notGranted: "mic.slash.fill"
            }
        }

        private var fill: Color {
            switch status {
            case .granted, .notRequested: .setupJade
            case .denied, .restricted, .notGranted: .gray
            }
        }
    }

    // MARK: Listening

    /// Before a choice, the three ways to listen take turns; after it, the chosen one, with a ring that fills
    /// while a model downloads.
    struct ListeningIllustration: View {
        let choice: SetupGuideModel.Listening?
        let modelState: ModelInstallState?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        enum Phase: CaseIterable { case device, speech, cloud }

        var body: some View {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 8)
                if let progress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.setupJade, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: progress)
                }
                symbolView
            }
            .frame(width: 116, height: 116)
            .padding(8)
            .accessibilityHidden(true)
        }

        @ViewBuilder private var symbolView: some View {
            if let symbol = chosenSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.setupJade)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, isActive: isWorking && !reduceMotion)
            } else {
                LoopingIllustration(phases: Phase.allCases, still: .device) { _ in
                    .smooth(duration: 0.5).delay(1.1)
                } content: { phase in
                    Image(systemName: Self.symbol(for: phase))
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Color.setupJade)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }

        private static func symbol(for phase: Phase) -> String {
            switch phase {
            case .device: "iphone"
            case .speech: "waveform"
            case .cloud: "cloud.fill"
            }
        }

        private var isWorking: Bool { progress != nil && progress ?? 0 < 1 }

        /// Shown only for a model download that is under way or done.
        private var progress: Double? {
            guard choice == .onDevice, let modelState else { return nil }
            switch modelState {
            case .downloading(let received, let total), .paused(let received, let total):
                return total > 0 ? Double(received) / Double(total) : 0
            case .verifying, .installed: return 1
            case .notInstalled, .failed: return nil
            }
        }

        private var chosenSymbol: String? {
            switch choice {
            case .onDevice:
                switch modelState {
                case .installed: "checkmark"
                case .downloading, .paused: "arrow.down"
                case .verifying: "checkmark.shield"
                default: "iphone"
                }
            case .appleSpeech: "waveform"
            case .cloud: "cloud.fill"
            case .later, nil: nil
            }
        }
    }

    // MARK: All set

    /// A seal that bounces in once when the step appears.
    struct DoneIllustration: View {
        @State private var appeared = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 96, weight: .semibold))
                .foregroundStyle(.white, Color.setupJade)
                .symbolEffect(.bounce, value: appeared)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .frame(width: 200, height: 180)
                .accessibilityHidden(true)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.spring(duration: 0.6, bounce: 0.5)) { appeared = true }
                }
        }
    }
#endif
