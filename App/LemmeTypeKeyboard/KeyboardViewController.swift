import SwiftUI
import UIKit

/// The LemmeType keyboard: normal typing keys that change to a recording view
/// during an Action Button dictation (ADR 0032).
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardVoiceModel()
    private let keys = TypingKeysView()
    private var overlay: UIHostingController<VoiceStatusView>?
    private var lastSpaceTime = Date.distantPast
    private var lastShiftTime = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        model.insertText = { [weak self] in self?.textDocumentProxy.insertText($0) }
        model.currentField = { [weak self] in self?.textDocumentProxy.documentIdentifier }
        model.onOverlayChange = { [weak self] in self?.updateOverlay() }

        keys.translatesAutoresizingMaskIntoConstraints = false
        keys.onAction = { [weak self] in self?.handle($0) }
        view.addSubview(keys)

        let host = UIHostingController(rootView: VoiceStatusView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.isHidden = true
        addChild(host)
        view.addSubview(host.view)
        overlay = host

        let height = view.heightAnchor.constraint(equalToConstant: TypingKeysView.preferredHeight)
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            height,
            keys.topAnchor.constraint(equalTo: view.topAnchor),
            keys.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keys.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keys.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.start()
        updateOverlay()
        updateAutoShift()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.stop()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        updateAutoShift()
    }

    /// The keys and the recording view share one space, so the keyboard never changes size.
    private func updateOverlay() {
        overlay?.view.isHidden = !model.showsOverlay
        keys.isHidden = model.showsOverlay
        // After dictating, the next thing someone types is almost always a word.
        if model.showsOverlay { keys.keyLayer = .letters }
    }

    private func handle(_ action: KeyAction) {
        switch action {
        case .character(let text):
            textDocumentProxy.insertText(text)
            if keys.shift == .once { keys.shift = .off }
        case .shift:
            toggleShift()
        case .delete:
            textDocumentProxy.deleteBackward()
        case .space:
            insertSpace()
        case .returnKey:
            textDocumentProxy.insertText("\n")
        case .layer(let layer):
            keys.keyLayer = layer
        }
        if action != .shift { updateAutoShift() }
    }

    private func toggleShift() {
        let now = Date.now
        defer { lastShiftTime = now }
        if keys.shift == .locked {
            keys.shift = .off
        } else if now.timeIntervalSince(lastShiftTime) < 0.35 {
            keys.shift = .locked
        } else {
            keys.shift = keys.shift == .off ? .once : .off
        }
    }

    private func insertSpace() {
        let now = Date.now
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let endsWord = before.dropLast().last?.isLetter == true || before.dropLast().last?.isNumber == true
        if now.timeIntervalSince(lastSpaceTime) < 0.6, before.hasSuffix(" "), endsWord {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            lastSpaceTime = .distantPast
        } else {
            textDocumentProxy.insertText(" ")
            lastSpaceTime = now
        }
        if keys.keyLayer != .letters { keys.keyLayer = .letters }
    }

    private func updateAutoShift() {
        guard keys.keyLayer == .letters, keys.shift != .locked else { return }
        keys.shift = shouldCapitalizeNext ? .once : .off
    }

    private var shouldCapitalizeNext: Bool {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: return false
        case .allCharacters: return true
        case .words: return before.isEmpty || before.last?.isWhitespace == true
        default:
            let trimmed = before.reversed().drop { $0 == " " }
            guard let last = trimmed.first else { return true }
            return last.isNewline || (trimmed.count < before.count && ".?!".contains(last))
        }
    }
}

/// The words also carry the state, so nothing depends on seeing the motion.
struct VoiceStatusView: View {
    let model: KeyboardVoiceModel

    var body: some View {
        VStack(spacing: 16) {
            if model.isListening {
                WaveformBars()
                Text("Listening…").font(.headline)
            } else if model.isWriting {
                Image(systemName: "text.cursor").font(.largeTitle).symbolEffect(.pulse)
                Text("Writing your text…").font(.headline)
            } else if let offered = model.offered {
                Text("Your text is ready").font(.headline)
                Text(offered.text).font(.subheadline).lineLimit(2).padding(.horizontal)
                HStack {
                    Button("Not Here", action: model.dismissOffered).buttonStyle(.bordered)
                    Button("Insert", action: model.insertOffered).buttonStyle(.borderedProminent)
                }
            } else if let message = model.failureMessage {
                Image(systemName: "exclamationmark.triangle").font(.title)
                Text(message).font(.subheadline).multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: model.offered == nil ? .combine : .contain)
    }
}

private struct WaveformBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<13, id: \.self) { index in
                    Capsule()
                        .frame(width: 6, height: 10 + 38 * Self.level(index: index, time: reduceMotion ? 0.5 : time))
                }
            }
            .frame(height: 50)
        }
        .accessibilityHidden(true)
    }

    private static func level(index: Int, time: Double) -> Double {
        let position = Double(index)
        return (sin(time * 7 + position * 0.9) + 1) / 2 * (sin(time * 2.3 + position * 0.4) + 1.4) / 2.4
    }
}
