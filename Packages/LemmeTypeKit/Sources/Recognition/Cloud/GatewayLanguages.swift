import Domain
import Foundation
import Synchronization

/// The Cloud speech languages the gateway serves right now (E12-S7). The gateway's routes decide;
/// the app only narrows the answer to the languages it can name (``SpokenLanguages/cloudCandidates``).
///
/// Read synchronously by ``GatewaySpeechProvider/supportedLanguages`` and written by
/// ``GatewayService`` each time it reads the gateway's capabilities. Until the gateway has answered
/// once, the list is Telugu: what version 1.0 shipped with.
public final class GatewayLanguages: Sendable {
    /// Before any answer: the language every gateway since 1.0 serves.
    public static let initial = [SpokenLanguages.telugu.code]

    private let store: any CloudLanguageStoring
    private let current: Mutex<[String]>

    public init(store: any CloudLanguageStoring) {
        self.store = store
        current = Mutex(Self.known(store.cloudLanguages ?? Self.initial))
    }

    /// The languages to offer, in the gateway's order.
    public var languages: [String] {
        current.withLock { $0 }
    }

    /// Records a new answer from the gateway. `true` when the list changed.
    @discardableResult
    public func update(_ answer: [String]) -> Bool {
        let languages = Self.known(answer)
        let changed = current.withLock { current -> Bool in
            guard current != languages else { return false }
            current = languages
            return true
        }
        if changed || store.cloudLanguages == nil { store.cloudLanguages = languages }
        return changed
    }

    /// Lowercase codes the app can name, each once. A language the app does not know is left out:
    /// it has no name to show, and no row in ``LanguageSupportMatrix``.
    static func known(_ codes: [String]) -> [String] {
        var seen: [String] = []
        for code in codes.map(SpokenLanguages.code(of:)) where SpokenLanguages.isCloudCandidate(code) {
            if !seen.contains(code) { seen.append(code) }
        }
        return seen
    }
}
