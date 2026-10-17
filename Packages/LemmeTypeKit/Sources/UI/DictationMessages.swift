import Domain

extension WritingMode {
    var displayName: String {
        switch self {
        case .exact: String(localized: "Exact Dictation", bundle: .module)
        case .clean: String(localized: "Clean Writing", bundle: .module)
        }
    }
}

extension DictationIssue {
    /// Concise, actionable text for the overlay. Never includes dictated text.
    var userMessage: String {
        switch self {
        case .recognitionFailed(.noSpeechDetected):
            String(localized: "No speech was detected.", bundle: .module)
        case .recognitionFailed(.permissionDenied), .engineUnavailable(_, .permissionUnavailable):
            String(
                localized: "Apple Speech needs Speech Recognition access. Your recording is kept until you decide.",
                bundle: .module)
        case .recognitionFailed(.assetsMissing), .engineUnavailable(_, .assetsMissing):
            String(localized: "The selected engine’s model isn’t installed. Your recording is kept.", bundle: .module)
        case .recognitionFailed(.unsupported), .engineUnavailable(_, .unsupported):
            String(
                localized: "The selected engine isn’t available on this Mac. Your recording is kept.", bundle: .module)
        case .recognitionFailed, .engineUnavailable:
            String(localized: "Transcription failed. Your recording is kept so you can try again.", bundle: .module)
        case .noEngineAvailable:
            String(localized: "No on-device engine is ready. Set one up in Settings.", bundle: .module)
        case .deliveryFailed(.targetChanged):
            String(
                localized: "The field you were typing in changed, so nothing was inserted. Copy the text or retry.",
                bundle: .module)
        case .deliveryFailed(.secureField):
            String(localized: "LemmeType never types into password fields. Copy the text instead.", bundle: .module)
        case .deliveryFailed(.permissionMissing):
            String(localized: "Accessibility access is needed to insert text. Copy it for now.", bundle: .module)
        case .deliveryFailed(.noTarget):
            String(localized: "There was no text field to insert into. Copy the text instead.", bundle: .module)
        case .deliveryFailed(.unsupported):
            String(localized: "This field doesn’t accept inserted text. Copy it instead.", bundle: .module)
        case .deliveryFailed(.pasteTimedOut):
            String(
                localized:
                    "The app didn’t take the pasted text in time. Your clipboard was put back; copy the text to paste it yourself.",
                bundle: .module)
        case .deliveryFailed(.clipboardUnsupported):
            String(
                localized:
                    "Your clipboard holds something LemmeType can’t put back, so it wasn’t used. Copying the text will replace it.",
                bundle: .module)
        case .deliveryFailed(.failed):
            String(
                localized: "LemmeType couldn’t confirm the text was inserted. Check the field, or copy the text.",
                bundle: .module)
        }
    }
}

extension DictationAction {
    func title(engineName: (RecognitionEngineID) -> String) -> String {
        switch self {
        case .retry: String(localized: "Retry", bundle: .module)
        case .useEngine(let engine): String(localized: "Use \(engineName(engine))", bundle: .module)
        case .allowSpeechRecognition: String(localized: "Allow Speech Recognition", bundle: .module)
        case .chooseEngine: String(localized: "Choose Engine…", bundle: .module)
        case .saveAudio: String(localized: "Save Audio…", bundle: .module)
        case .copyText: String(localized: "Copy Text", bundle: .module)
        case .retryDelivery: String(localized: "Retry Insert", bundle: .module)
        case .openPermissions: String(localized: "Open Permissions", bundle: .module)
        case .discard: String(localized: "Discard", bundle: .module)
        }
    }

    /// Stable accessibility identifier suffix.
    var identifier: String {
        switch self {
        case .retry: "retry"
        case .useEngine(let engine): "use-\(engine.rawValue)"
        case .allowSpeechRecognition: "allow-speech"
        case .chooseEngine: "choose-engine"
        case .saveAudio: "save-audio"
        case .copyText: "copy-text"
        case .retryDelivery: "retry-delivery"
        case .openPermissions: "open-permissions"
        case .discard: "discard"
        }
    }
}

extension RecognitionEngineID {
    /// Display name for engine pickers and buttons.
    var displayName: String {
        switch self {
        case .appleSpeech: String(localized: "Apple Speech", bundle: .module)
        case .whisper: String(localized: "Whisper", bundle: .module)
        default: rawValue
        }
    }
}

extension DeliveryMethod {
    /// Announced to VoiceOver and shown under "Done".
    var announcement: String {
        switch self {
        case .accessibility: String(localized: "Text inserted.", bundle: .module)
        case .paste: String(localized: "Text pasted.", bundle: .module)
        case .copied: String(localized: "Text copied. Press ⌘V to paste it.", bundle: .module)
        }
    }
}

extension WritingMode {
    /// Plain-language behaviour, shown before the user picks a mode.
    var summary: String {
        switch self {
        case .exact:
            String(
                localized: "Types exactly the words that were recognised. Only extra spaces are removed.",
                bundle: .module)
        case .clean:
            String(
                localized:
                    "Adds capitals and end punctuation, turns spoken “comma” or “new line” into punctuation, and drops “um”, repeated words, and clear self-corrections like “Tuesday—sorry—Wednesday”. Numbers, links, email addresses, code, and quotes are never changed.",
                bundle: .module)
        }
    }
}

extension ProcessingPhase {
    var title: String {
        switch self {
        case .preparingEngine: String(localized: "Preparing…", bundle: .module)
        case .recognizing: String(localized: "Transcribing…", bundle: .module)
        case .writing: String(localized: "Writing…", bundle: .module)
        case .delivering: String(localized: "Inserting…", bundle: .module)
        }
    }
}
