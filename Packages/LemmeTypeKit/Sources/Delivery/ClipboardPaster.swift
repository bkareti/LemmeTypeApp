import Domain

/// How long the clipboard fallback waits for the target to take the text.
struct PasteTiming: Sendable {
    /// Used when the target's character count can't be observed.
    var restoreDelay: Duration
    /// Longest wait for an observable target before giving up.
    var timeout: Duration = .seconds(2)
    var pollInterval: Duration = .milliseconds(50)
}

/// Pastes final text through the clipboard and puts the previous clipboard
/// back (E2-S8, docs/decisions/0015-text-delivery.md).
///
/// The previous contents are restored only if nothing else changed the
/// clipboard since LemmeType wrote to it, so a user's newer copy is never
/// overwritten. A clipboard that can't be restored completely is left alone.
/// Clipboard contents are held in memory for one paste and never logged.
struct ClipboardPaster<Driver: AccessibilityDriving>: Sendable {
    let driver: Driver
    let pasteboard: any PasteboardAccessing
    let keystroke: any PasteKeystrokePosting
    let diagnostics: any DiagnosticsRecording
    let sleep: @Sendable (Duration) async -> Void

    /// Pastes `text` once and restores the previous clipboard.
    ///
    /// - Parameters:
    ///   - text: The final text.
    ///   - element: The validated target element, used to observe when the
    ///     paste lands; `nil` when it can't be observed.
    ///   - timing: Restore delay and timeout.
    /// - Returns: `.delivered(.paste)`, or why the paste wasn't confirmed.
    func paste(_ text: String, into element: Driver.Element?, timing: PasteTiming) async -> DeliveryOutcome {
        if driver.isSecureInputActive() { return .problem(.secureField) }
        let snapshot = await pasteboard.snapshot()
        guard snapshot.isComplete else { return .problem(.clipboardUnsupported) }
        let before = element.flatMap { driver.characterCount(of: $0) }
        let written = await pasteboard.writeTransient(text)
        guard keystroke.postPaste() else {
            await restore(snapshot, ifStillAt: written)
            return .problem(.failed)
        }

        let start = ContinuousClock.now
        let consumed: Bool
        if let element, let before {
            consumed = await waitForChange(of: element, from: before, timing: timing)
        } else {
            await sleep(timing.restoreDelay)
            consumed = true
        }
        await restore(snapshot, ifStillAt: written)
        diagnostics.record(
            .delivery, "clipboard.pasted",
            [
                "observed": .flag(element != nil && before != nil), "consumed": .flag(consumed),
                "waitSeconds": .seconds((ContinuousClock.now - start).seconds),
            ])
        return consumed ? .delivered(.paste) : .problem(.pasteTimedOut)
    }

    private func waitForChange(of element: Driver.Element, from before: Int, timing: PasteTiming) async -> Bool {
        var waited = Duration.zero
        while waited < timing.timeout {
            if let count = driver.characterCount(of: element), count != before { return true }
            await sleep(timing.pollInterval)
            waited += timing.pollInterval
        }
        return driver.characterCount(of: element).map { $0 != before } ?? false
    }

    private func restore(_ snapshot: PasteboardSnapshot, ifStillAt written: Int) async {
        guard await pasteboard.changeCount() == written else {
            // Someone copied something newer; keep it.
            diagnostics.record(.delivery, "clipboard.restore-skipped")
            return
        }
        await pasteboard.restore(snapshot)
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
