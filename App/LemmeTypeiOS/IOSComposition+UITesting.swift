#if DEBUG
    import Audio
    import Domain
    import Foundation
    import Support
    import TestSupport

    /// Debug-only fakes for UI tests (`-LemmeTypeUITesting`), and the scenario a test asks
    /// them to play. Nothing here touches the microphone, a speech engine, or the pasteboard.
    extension IOSComposition {
        /// What a UI test asks of the fakes, from launch arguments that follow
        /// `-LemmeTypeUITesting`. Anything absent keeps the happy path: the microphone is
        /// granted, a tone is "recorded", and the engine returns a fixed sentence.
        struct UITestScenario: Equatable {
            static let microphoneArgument = "-LemmeTypeMicrophone"
            static let microphoneAnswerArgument = "-LemmeTypeMicrophoneAnswer"
            static let recordingLimitArgument = "-LemmeTypeRecordingLimit"
            static let interruptAfterArgument = "-LemmeTypeInterruptAfter"
            static let recognitionArgument = "-LemmeTypeRecognition"
            static let launchRequestArgument = "-LemmeTypeLaunchRequest"
            /// The words the fake engine "hears" (App Store screenshots), from the environment so
            /// punctuation survives; otherwise a fixed phrase.
            static let recognizedTextVariable = "LEMMETYPE_RECOGNIZED_TEXT"

            /// The microphone permission at launch: `granted`, `notRequested`, `denied`, or `restricted`.
            var microphone: PermissionStatus = .granted
            /// What the system microphone prompt resolves to.
            var microphoneAnswer: PermissionStatus = .granted
            /// A shorter recording limit in seconds, so a test reaches it; otherwise `.handheld`.
            var recordingLimit: RecordingLimits = .handheld
            /// An interruption (a call, Siri, an alarm) this many seconds into a recording.
            var interruptsAfter: Duration?
            /// `no-speech` makes the engine find no speech.
            var recognitionError: RecognitionError?
            /// A shortcut left a launch request, as the App Intent does (E8-S7).
            var startsFromShortcut = false
            var recognizedText = "hello from lemmetype"

            init() {}

            init(arguments: [String]) {
                func value(after flag: String) -> String? {
                    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
                    return arguments[index + 1]
                }
                func seconds(after flag: String) -> Duration? {
                    value(after: flag).flatMap(Double.init).map { .milliseconds(Int($0 * 1_000)) }
                }
                if let status = value(after: Self.microphoneArgument).flatMap(PermissionStatus.init(rawValue:)) {
                    microphone = status
                }
                if let answer = value(after: Self.microphoneAnswerArgument).flatMap(PermissionStatus.init(rawValue:)) {
                    microphoneAnswer = answer
                }
                if let limit = seconds(after: Self.recordingLimitArgument) {
                    recordingLimit = RecordingLimits(maximumDuration: limit)
                }
                interruptsAfter = seconds(after: Self.interruptAfterArgument)
                if value(after: Self.recognitionArgument) == "no-speech" { recognitionError = .noSpeechDetected }
                startsFromShortcut = arguments.contains(Self.launchRequestArgument)
                if let text = ProcessInfo.processInfo.environment[Self.recognizedTextVariable] { recognizedText = text }
            }
        }

        static func uiTesting(_ scenario: UITestScenario) -> Services {
            let diagnostics = DiagnosticsBuffer()
            let copier = FakeTextDelivery()
            let permissions = FakePermissions(
                statuses: [.microphone: scenario.microphone], microphoneAnswer: scenario.microphoneAnswer,
                grantsAccessibilityOnRequest: false)
            let preferences = FakePreferences(hasCompletedOnboarding: true)
            return Services(
                permissionChecker: permissions,
                permissionRequester: permissions,
                preferences: preferences,
                audioCapture: AudioCaptureService(
                    source: FakeAudioSource(liveTone: true, interruptsAfter: scenario.interruptsAfter),
                    storage: AudioSessionStorage(
                        directory: FileManager.default.temporaryDirectory
                            .appendingPathComponent("LemmeTypeUITesting", isDirectory: true)),
                    permissions: permissions, diagnostics: diagnostics),
                speechAuthorizer: FakeSpeechAuthorizer(status: .granted),
                engines: [
                    FakeRecognitionEngine(
                        id: .appleSpeech,
                        script: .init(text: scenario.recognizedText, error: scenario.recognitionError)),
                    FakeRecognitionEngine(
                        id: .whisper, availability: .assetsMissing, assets: .downloadable(.whisperBaseEnglish)),
                ],
                modelAssets: FakeModelAssetManager(),
                textCopier: copier,
                rewriter: FakeTextRewriter(),
                personalizationStore: FakePersonalizationStore(),
                historyStore: FakeDictationHistoryStore(),
                conditions: FakeSystemConditions(),
                diagnostics: diagnostics,
                hardware: HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 8 << 30, deviceClass: .iPhone),
                copiedTextLifetime: { .default },
                limits: scenario.recordingLimit)
        }
    }
#endif
