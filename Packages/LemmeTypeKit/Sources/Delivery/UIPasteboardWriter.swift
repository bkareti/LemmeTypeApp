#if os(iOS)
    import Domain
    import Support
    import UIKit
    import UniformTypeIdentifiers

    /// Writes the reviewed text to the iOS general pasteboard (ADR 0027): the item
    /// is local-only, so Universal Clipboard never sends it to another device, and
    /// it expires, so it does not wait there for the next app to read it. The text
    /// is never logged.
    @MainActor
    public struct UIPasteboardWriter: ExpiringPasteboardWriting {
        public init() {}

        public func write(_ text: String, lifetime: TimeInterval) {
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: text]],
                options: [
                    .localOnly: true,
                    .expirationDate: Date(timeIntervalSinceNow: lifetime),
                ])
            Log.delivery.info("Text copied to the pasteboard; expires in \(Int(lifetime), privacy: .public)s")
        }
    }
#endif
