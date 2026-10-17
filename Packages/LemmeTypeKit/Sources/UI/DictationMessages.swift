import Domain

extension WritingMode {
    var displayName: String {
        switch self {
        case .exact: String(localized: "Exact Dictation", bundle: .module)
        case .clean: String(localized: "Clean Writing", bundle: .module)
        }
    }
}

extension DictationMode {
    /// Built-in names are localized; custom modes show the user's name.
    public var displayName: String {
        switch id {
        case .exact: WritingMode.exact.displayName
        case .clean: WritingMode.clean.displayName
        case .message: String(localized: "Message", bundle: .module)
        default: name
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
        case .editingUnavailable(let reason):
            reason.editingMessage
        case .rewriterUnavailable(let availability):
            availability.userMessage
        case .rewriteFailed(.refused):
            String(
                localized: "The on-device model declined this edit. Your text is unchanged.", bundle: .module)
        case .rewriteFailed(.tooLong):
            String(localized: "The selection is too long to edit. Select less text.", bundle: .module)
        case .rewriteFailed:
            String(localized: "The edit didn’t work. Your text is unchanged.", bundle: .module)
        }
    }
}

extension ContextBlockReason {
    /// Why a voice edit can't start.
    var editingMessage: String {
        switch self {
        case .noSelection, .unreadable:
            String(localized: "Select the text you want to change, then press the shortcut.", bundle: .module)
        case .selectionTooLong:
            String(localized: "The selection is too long to edit. Select less text.", bundle: .module)
        case .secureField, .secureInput:
            String(localized: "LemmeType never reads password fields.", bundle: .module)
        case .sensitiveApp:
            String(localized: "LemmeType never reads text in password managers.", bundle: .module)
        case .excludedApp:
            String(localized: "You turned off context for this app in Settings › Context.", bundle: .module)
        case .editingDisabled, .disabled:
            String(localized: "Voice editing is turned off in Settings › Context.", bundle: .module)
        case .noAccessibility:
            String(localized: "Voice editing needs Accessibility access.", bundle: .module)
        }
    }
}

extension ContextCapture {
    /// The overlay's context line; `nil` when there is nothing worth saying
    /// (not requested, or formatting context switched off by the user).
    var statusText: String? {
        switch self {
        case .notRequested, .blocked(.disabled, _), .captured(_, .editing), .blocked(_, .editing):
            nil
        case .captured(_, .formatting):
            String(localized: "Using text near the cursor", bundle: .module)
        case .blocked(.excludedApp, _):
            String(localized: "Context off for this app", bundle: .module)
        case .blocked(.sensitiveApp, _), .blocked(.secureField, _), .blocked(.secureInput, _):
            String(localized: "Context not read here (private field or app)", bundle: .module)
        case .blocked:
            String(localized: "Context not available in this field", bundle: .module)
        }
    }
}

extension RewriterAvailability {
    var userMessage: String {
        switch self {
        case .ready:
            String(localized: "The on-device model is ready.", bundle: .module)
        case .notEnabled:
            String(
                localized:
                    "Voice editing needs Apple Intelligence. Turn it on in System Settings › Apple Intelligence & Siri.",
                bundle: .module)
        case .deviceNotEligible:
            String(
                localized: "This Mac can’t run Apple’s on-device model, so voice editing isn’t available.",
                bundle: .module)
        case .modelNotReady:
            String(
                localized: "Apple’s on-device model is still getting ready. Try again in a few minutes.",
                bundle: .module)
        case .unsupportedLanguage:
            String(localized: "The on-device model doesn’t support your dictation language yet.", bundle: .module)
        case .unavailable:
            String(localized: "Voice editing isn’t available right now.", bundle: .module)
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
        case .openContextSettings: String(localized: "Context Settings…", bundle: .module)
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
        case .openContextSettings: "open-context-settings"
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
        case .rewriting: String(localized: "Rewriting on this Mac…", bundle: .module)
        case .delivering: String(localized: "Inserting…", bundle: .module)
        }
    }
}
