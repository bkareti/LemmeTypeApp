import UIKit

enum KeyLayer: Equatable {
    case letters, numbers, symbols
}

enum ShiftState: Equatable {
    case off, once, locked
}

enum KeyAction: Equatable {
    case character(String)
    case shift
    case delete
    case space
    case returnKey
    case layer(KeyLayer)
}

/// Draws the keys and tracks fingers itself: every touch goes to the nearest key, so the gaps
/// between keys are not dead zones, and two thumbs can overlap while typing quickly.
final class TypingKeysView: UIView {
    var onAction: (KeyAction) -> Void = { _ in }

    var keyLayer: KeyLayer = .letters {
        didSet { if keyLayer != oldValue { rebuild() } }
    }
    var shift: ShiftState = .off {
        didSet { if shift != oldValue { rebuild() } }
    }

    private struct Definition {
        var title: String?
        var symbol: String?
        var action: KeyAction
        var weight: CGFloat = 1
        var isSpecial = false
        var accessibility: String
    }

    private struct Row {
        var keys: [Definition]
        var insetInKeys: CGFloat = 0
    }

    private var keyViews: [KeyView] = []
    private var activeTouches: [ObjectIdentifier: KeyView] = [:]
    private var repeatTimer: Timer?

    private static let keyHeight: CGFloat = 46
    private static let rowGap: CGFloat = 11
    private static let keyGap: CGFloat = 6
    private static let side: CGFloat = 4
    private static let top: CGFloat = 8
    static let preferredHeight: CGFloat = top + keyHeight * 4 + rowGap * 3 + 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used: this view is created in code.") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutKeys()
    }

    private func letter(_ text: String) -> Definition {
        let shown = shift == .off ? text : text.uppercased()
        return Definition(title: shown, action: .character(shown), accessibility: shown)
    }

    private func typed(_ text: String, weight: CGFloat = 1) -> Definition {
        Definition(title: text, action: .character(text), weight: weight, accessibility: text)
    }

    private var shiftKey: Definition {
        let symbol =
            switch shift {
            case .off: "shift"
            case .once: "shift.fill"
            case .locked: "capslock.fill"
            }
        return Definition(symbol: symbol, action: .shift, weight: 1.45, isSpecial: true, accessibility: "Shift")
    }

    private var deleteKey: Definition {
        Definition(symbol: "delete.left", action: .delete, weight: 1.45, isSpecial: true, accessibility: "Delete")
    }

    private func bottomRow(switchTitle: String, to target: KeyLayer) -> Row {
        Row(keys: [
            Definition(
                title: switchTitle, action: .layer(target), weight: 2.45, isSpecial: true, accessibility: switchTitle),
            Definition(title: "LemmeType", action: .space, weight: 5.9, accessibility: "Space"),
            Definition(
                symbol: "return.left", action: .returnKey, weight: 2.45, isSpecial: true, accessibility: "Return"),
        ])
    }

    private func letterRows() -> [Row] {
        [
            Row(keys: "qwertyuiop".map { letter(String($0)) }),
            Row(keys: "asdfghjkl".map { letter(String($0)) }, insetInKeys: 0.5),
            Row(keys: [shiftKey] + "zxcvbnm".map { letter(String($0)) } + [deleteKey]),
            bottomRow(switchTitle: "123", to: .numbers),
        ]
    }

    private func punctuationRow(switchTitle: String, to target: KeyLayer) -> Row {
        let change = Definition(
            title: switchTitle, action: .layer(target), weight: 1.45, isSpecial: true, accessibility: switchTitle)
        return Row(keys: [change] + [".", ",", "?", "!", "'"].map { typed($0, weight: 1.42) } + [deleteKey])
    }

    private func numberRows() -> [Row] {
        [
            Row(keys: "1234567890".map { typed(String($0)) }),
            Row(keys: ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { typed($0) }),
            punctuationRow(switchTitle: "#+=", to: .symbols),
            bottomRow(switchTitle: "ABC", to: .letters),
        ]
    }

    private func symbolRows() -> [Row] {
        [
            Row(keys: ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { typed($0) }),
            Row(keys: ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"].map { typed($0) }),
            punctuationRow(switchTitle: "123", to: .numbers),
            bottomRow(switchTitle: "ABC", to: .letters),
        ]
    }

    private var rows: [Row] {
        switch keyLayer {
        case .letters: letterRows()
        case .numbers: numberRows()
        case .symbols: symbolRows()
        }
    }

    private func rebuild() {
        clearTouches()
        keyViews.forEach { $0.removeFromSuperview() }
        keyViews = rows.enumerated().flatMap { rowIndex, row in
            row.keys.map { definition in
                let view = KeyView(
                    title: definition.title, symbol: definition.symbol, isSpecial: definition.isSpecial,
                    accessibility: definition.accessibility)
                view.action = definition.action
                view.rowIndex = rowIndex
                view.weight = definition.weight
                view.onActivate = { [weak self] in self?.onAction(definition.action) }
                addSubview(view)
                return view
            }
        }
        setNeedsLayout()
    }

    private func layoutKeys() {
        let allRows = rows
        let keyUnit = (bounds.width - Self.side * 2 - Self.keyGap * 9) / 10
        for (rowIndex, row) in allRows.enumerated() {
            let inset = Self.side + row.insetInKeys * (keyUnit + Self.keyGap)
            let available = bounds.width - inset * 2 - Self.keyGap * CGFloat(row.keys.count - 1)
            let unit = available / row.keys.reduce(0) { $0 + $1.weight }
            let y = Self.top + CGFloat(rowIndex) * (Self.keyHeight + Self.rowGap)
            var x = inset
            for view in keyViews where view.rowIndex == rowIndex {
                let width = unit * view.weight
                view.frame = CGRect(x: x, y: y, width: width, height: Self.keyHeight)
                x += width + Self.keyGap
            }
        }
    }

    private func nearestKey(to point: CGPoint) -> KeyView? {
        keyViews.min { distance(point, $0.frame) < distance(point, $1.frame) }
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let horizontal = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let vertical = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return horizontal * horizontal + vertical * vertical
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let key = nearestKey(to: touch.location(in: self)) else { continue }
            activeTouches[ObjectIdentifier(touch)] = key
            key.setPressed(true)
            if key.action == .delete {
                onAction(.delete)
                startDeleteRepeat()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let current = activeTouches[id], current.action != .delete,
                let key = nearestKey(to: touch.location(in: self)), key !== current
            else { continue }
            current.setPressed(false)
            key.setPressed(true)
            activeTouches[id] = key
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Collected first: an action can rebuild the keys and clear the active touches.
        var actions: [KeyAction] = []
        for touch in touches {
            guard let key = activeTouches.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            key.setPressed(false)
            if key.action == .delete {
                stopTimers()
            } else {
                actions.append(key.action)
            }
        }
        actions.forEach(onAction)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            activeTouches.removeValue(forKey: ObjectIdentifier(touch))?.setPressed(false)
        }
        stopTimers()
    }

    private func clearTouches() {
        activeTouches.values.forEach { $0.setPressed(false) }
        activeTouches.removeAll()
        stopTimers()
    }

    private func startDeleteRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onAction(.delete) }
                }
            }
        }
    }

    private func stopTimers() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

private final class KeyView: UIView {
    var action = KeyAction.space
    var rowIndex = 0
    var weight: CGFloat = 1
    var onActivate: () -> Void = {}

    private let isSpecial: Bool

    private static let normal = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    }
    private static let special = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(white: 0.72, alpha: 1)
    }

    init(title: String?, symbol: String?, isSpecial: Bool, accessibility: String) {
        self.isSpecial = isSpecial
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = 9
        layer.cornerCurve = .continuous
        backgroundColor = isSpecial ? Self.special : Self.normal

        let content: UIView
        if let symbol {
            let image = UIImageView(image: UIImage(systemName: symbol))
            image.tintColor = .label
            image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
            content = image
        } else {
            let label = UILabel()
            label.text = title
            label.textColor = .label
            label.font = .systemFont(ofSize: (title?.count ?? 0) > 1 ? 16 : 22)
            content = label
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        isAccessibilityElement = true
        accessibilityLabel = accessibility
        accessibilityTraits = .keyboardKey
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used: this view is created in code.") }

    func setPressed(_ pressed: Bool) {
        backgroundColor = pressed != isSpecial ? Self.special : Self.normal
    }

    override func accessibilityActivate() -> Bool {
        onActivate()
        return true
    }
}
