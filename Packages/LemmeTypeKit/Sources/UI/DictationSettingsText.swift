import Domain
import Foundation

/// User-facing words for the Dictation pane and the status menu. Never
/// includes dictated text.
extension DictationSettingsModel {
    /// Why Automatic picks what it picks, in plain language.
    public var automaticExplanation: String {
        let ready = rows.filter { $0.isReady && supports($0, language) }
        guard let first = ready.first else {
            return String(localized: "No on-device engine is ready yet.", bundle: .module)
        }
        if ready.count == 1 {
            return String(
                localized: "Uses \(first.id.displayName), the only engine ready on this Mac.", bundle: .module)
        }
        return String(
            localized: "Uses \(first.id.displayName), the recommended engine that is ready on this Mac.",
            bundle: .module)
    }

    /// One line for the status menu, for example "Engine: Automatic (Apple Speech) · On this Mac".
    public var menuEngineSummary: String {
        let location = String(localized: "On this Mac", bundle: .module)
        guard let effective = effectiveEngine else {
            return String(localized: "Engine: not ready", bundle: .module)
        }
        if selectedEngine == nil {
            return String(localized: "Engine: Automatic (\(effective.displayName)) · \(location)", bundle: .module)
        }
        return String(localized: "Engine: \(effective.displayName) · \(location)", bundle: .module)
    }

    nonisolated static func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}

extension DictationSettingsModel.EngineRow {
    /// Location, languages, and what has to be installed.
    var detail: String {
        let location = String(localized: "On this Mac", bundle: .module)
        let languages = ListFormatter.localizedString(byJoining: languages.map(DictationSettingsModel.languageName))
        let download: String
        switch assets {
        case .none:
            download = String(localized: "No download", bundle: .module)
        case .systemManaged:
            download = String(localized: "Uses macOS dictation languages", bundle: .module)
        case .downloadable(let id):
            let size = ModelCatalog.asset(id)?.downloadBytes.formatted(.byteCount(style: .file)) ?? ""
            download = String(localized: "\(size) download", bundle: .module)
        }
        return [location, languages, download].joined(separator: " · ")
    }
}

extension EngineAvailability {
    var statusTitle: String {
        switch self {
        case .ready: String(localized: "Ready", bundle: .module)
        case .assetsMissing: String(localized: "Download required", bundle: .module)
        case .permissionUnavailable: String(localized: "Needs Speech Recognition access", bundle: .module)
        case .unsupported(.language): String(localized: "Doesn’t support this language", bundle: .module)
        case .unsupported: String(localized: "Not available on this Mac", bundle: .module)
        case .failed: String(localized: "Couldn’t start", bundle: .module)
        }
    }
}

extension UnsupportedReason {
    var explanation: String {
        switch self {
        case .operatingSystem: String(localized: "Needs a newer version of macOS.", bundle: .module)
        case .hardware: String(localized: "Needs a Mac with Apple silicon.", bundle: .module)
        case .insufficientMemory: String(localized: "Needs a Mac with at least 8 GB of memory.", bundle: .module)
        case .language: String(localized: "Doesn’t support the selected language.", bundle: .module)
        case .onDeviceRecognitionUnavailable:
            String(
                localized:
                    "On-device recognition isn’t installed for this language. Add it in System Settings › Keyboard › Dictation.",
                bundle: .module)
        }
    }
}

extension ModelInstallState {
    var statusTitle: String {
        switch self {
        case .notInstalled: String(localized: "Not downloaded", bundle: .module)
        case .downloading(let received, let total):
            String(
                localized:
                    "Downloading \(received.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))",
                bundle: .module)
        case .paused(let received, let total):
            String(
                localized:
                    "Paused at \(received.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))",
                bundle: .module)
        case .verifying: String(localized: "Verifying…", bundle: .module)
        case .installed: String(localized: "Installed and verified", bundle: .module)
        case .failed(let error): error.userMessage
        }
    }
}

extension ModelAssetError {
    var userMessage: String {
        switch self {
        case .insufficientStorage(let required, let available):
            String(
                localized:
                    "Not enough free space: \(required.formatted(.byteCount(style: .file))) needed, \(available.formatted(.byteCount(style: .file))) available.",
                bundle: .module)
        case .downloadFailed:
            String(localized: "The download failed. Check your connection and try again.", bundle: .module)
        case .digestMismatch, .sizeMismatch:
            String(localized: "The downloaded file didn’t pass verification and was deleted.", bundle: .module)
        case .alreadyInProgress:
            String(localized: "This model is already downloading.", bundle: .module)
        case .storageFailure:
            String(localized: "The model couldn’t be saved on this Mac.", bundle: .module)
        case .consentRequired, .unknownAsset, .untrustedSource:
            String(localized: "This model can’t be downloaded.", bundle: .module)
        }
    }
}

extension DictationSettingsModel.DownloadOffer {
    var confirmationMessage: String {
        let size = asset.downloadBytes.formatted(.byteCount(style: .file))
        let storage = asset.installedBytes.formatted(.byteCount(style: .file))
        let free = availableBytes.formatted(.byteCount(style: .file))
        var message = String(
            localized:
                "Downloads \(size) from Hugging Face and uses \(storage) on this Mac. Licence: \(asset.license). Free space: \(free). The file is verified before use; dictation itself never uses the network.",
            bundle: .module)
        if !hasEnoughSpace {
            let required = asset.requiredFreeBytes.formatted(.byteCount(style: .file))
            message += "\n\n" + String(localized: "You need at least \(required) free.", bundle: .module)
        }
        return message
    }
}

extension ClipboardFallback {
    var title: String {
        switch self {
        case .pasteAndRestore: String(localized: "Paste, then restore my clipboard", bundle: .module)
        case .copyOnly: String(localized: "Copy only (I’ll paste)", bundle: .module)
        case .off: String(localized: "Ask me (Copy Text)", bundle: .module)
        }
    }

    var explanation: String {
        switch self {
        case .pasteAndRestore:
            String(
                localized:
                    "Some apps don’t accept typed text. LemmeType then pastes it and puts back what was on your clipboard — unless you copied something new meanwhile.",
                bundle: .module)
        case .copyOnly:
            String(
                localized:
                    "The text is left on the clipboard for you to paste with ⌘V. Your previous clipboard is replaced.",
                bundle: .module)
        case .off:
            String(localized: "Nothing is pasted automatically; the overlay offers Copy Text.", bundle: .module)
        }
    }
}
