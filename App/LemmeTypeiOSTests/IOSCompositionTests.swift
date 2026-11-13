import Domain
import Foundation
import Security
import Support
import Testing
import UI

@testable import LemmeTypeiOS

/// E8-S4, E8-S6: the iPhone composition wires the shared pieces the way ADR 0027 says.
@MainActor
struct IOSCompositionTests {
    private func makeComposition() -> IOSComposition {
        IOSComposition.make(arguments: [IOSComposition.uiTestingArgument])
    }

    @Test func uiTestingModeUsesFakesAndStartsReady() {
        let composition = makeComposition()

        #expect(composition.mode == .uiTesting)
        #expect(composition.quick.screen == .ready)
        #expect(composition.recorder.state == .idle)
    }

    @Test func aDebugBuildOffersCloudSpeechButItStartsOff() async {
        let composition = makeComposition()
        #expect(IOSComposition.offersCloudSpeech)
        let cloudSpeech = composition.cloudSpeech
        await cloudSpeech?.refresh()
        #expect(cloudSpeech?.status == .off)
        #expect(!composition.modes.engines.contains(.cloud))
    }

    @Test func aReleaseBuildOffersCloudSpeechOnlyWhenTheProductionHostIsSet() {
        #expect(IOSComposition.releaseGatewayHost(from: nil) == nil)
        #expect(IOSComposition.releaseGatewayHost(from: [:]) == nil)
        #expect(IOSComposition.releaseGatewayHost(from: ["LemmeTypeGatewayHost": ""]) == nil, "an empty setting is off")
        #expect(IOSComposition.releaseGatewayHost(from: ["LemmeTypeGatewayHost": " \n"]) == nil)
        #expect(
            IOSComposition.releaseGatewayHost(from: ["LemmeTypeGatewayHost": "api.example.com"]) == "api.example.com")
    }

    @Test func anOldApiKeyInTheKeychainIsRemoved() throws {
        let service = "com.lemmetype.tests.\(UUID().uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "sarvam", kSecValueData as String: Data("old-key".utf8),
        ]
        #expect(SecItemAdd(query as CFDictionary, nil) == errSecSuccess)
        let eraser = LegacyCloudKeyEraser(service: service)
        #expect(eraser.erase(), "a stored key was found and removed")
        #expect(!eraser.erase(), "nothing is left, and erasing again is harmless")
    }

    @Test func aRecordingHasATimeLimit() {
        #expect(makeComposition().recorder.limits == .handheld)
    }

    @Test func theIntentAndTheAppShareOneLaunchInbox() {
        let composition = makeComposition()

        composition.launchRequests.post()

        #expect(composition.launchRequests.consume() != nil)
        #expect(composition.launchRequests.consume() == nil)
    }

    @Test func aDictationEndsInAReviewAndIsNeverCopiedAutomatically() async throws {
        let composition = makeComposition()

        composition.quick.start()
        await composition.recorder.settle()
        #expect(composition.quick.screen == .recording)
        try await Task.sleep(for: .milliseconds(400))
        composition.quick.stop()
        await composition.recorder.settle()

        #expect(composition.quick.screen == .review(text: "hello from lemmetype"))
        composition.quick.discard()
        await composition.recorder.settle()
        #expect(composition.quick.screen == .ready)
    }

    @Test func copyConfirmsAndLeavesNothingBehind() async throws {
        let composition = makeComposition()
        composition.quick.start()
        await composition.recorder.settle()
        try await Task.sleep(for: .milliseconds(400))
        composition.quick.stop()
        await composition.recorder.settle()

        await composition.quick.copy()

        #expect(composition.quick.copiedFor == .twoMinutes)
        #expect(composition.quick.screen == .ready)
    }

    @Test func aUITestCanAskForAScenario() {
        typealias Scenario = IOSComposition.UITestScenario
        let scenario = Scenario(arguments: [
            IOSComposition.uiTestingArgument, Scenario.microphoneArgument, "notRequested",
            Scenario.microphoneAnswerArgument, "denied", Scenario.recordingLimitArgument, "2",
            Scenario.interruptAfterArgument, "0.5", Scenario.recognitionArgument, "no-speech",
            Scenario.launchRequestArgument,
        ])

        #expect(scenario.microphone == .notRequested)
        #expect(scenario.microphoneAnswer == .denied)
        #expect(scenario.recordingLimit == RecordingLimits(maximumDuration: .seconds(2)))
        #expect(scenario.interruptsAfter == .milliseconds(500))
        #expect(scenario.recognitionError == .noSpeechDetected)
        #expect(scenario.startsFromShortcut)
        #expect(Scenario(arguments: [IOSComposition.uiTestingArgument]) == Scenario())
    }

    @Test func theScenarioReachesTheRecorderAndTheLaunchInbox() {
        let composition = IOSComposition.make(arguments: [
            IOSComposition.uiTestingArgument, IOSComposition.UITestScenario.recordingLimitArgument, "2",
            IOSComposition.UITestScenario.launchRequestArgument,
        ])

        #expect(composition.recorder.limits == RecordingLimits(maximumDuration: .seconds(2)))
        #expect(composition.launchRequests.consume() != nil)
    }

    @Test func aDeniedMicrophoneScenarioNeverRecords() async {
        let composition = IOSComposition.make(arguments: [
            IOSComposition.uiTestingArgument, IOSComposition.UITestScenario.microphoneArgument, "denied",
        ])

        composition.quick.start()
        await composition.recorder.settle()

        #expect(composition.quick.screen == .failed(.microphonePermissionMissing))
    }

    @Test func theSimulatorDoesNotRefuseModelsForMemoryItCannotMeasure() {
        #if targetEnvironment(simulator)
            #expect(IOSComposition.availableMemory() == nil)
        #else
            #expect(IOSComposition.availableMemory() != nil)
        #endif
    }

    @Test func whisperRunsOnTheCPUInTheSimulator() {
        #if targetEnvironment(simulator)
            #expect(!IOSComposition.gpuRunsWhisper)
        #else
            #expect(IOSComposition.gpuRunsWhisper)
        #endif
    }

    // MARK: On-device evaluation

    @Test func anEvaluationIsRequestedOnlyWithAModel() {
        typealias Request = IOSComposition.EvaluationRequest
        #expect(Request(arguments: [Request.argument]) == nil)
        #expect(Request(arguments: []) == nil)

        let request = Request(arguments: [
            Request.argument, "whisper-base", Request.taskArgument, "translate-to-english", Request.modeArgument,
            "exact", Request.languagesArgument, "hi,te", Request.labelArgument, "iphone-16",
        ])
        var expected = Request(model: .whisperBase)
        expected.task = "translate-to-english"
        expected.mode = "exact"
        expected.languages = "hi,te"
        expected.label = "iphone-16"
        #expect(request == expected)
    }

    @Test(arguments: [
        ("nope", "evaluation.unknown-model"),
        ("whisper-base", "evaluation.no-manifests"),
    ])
    func aFailedEvaluationSaysWhyInItsStatus(model: String, reason: String) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-IOSEvaluation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("manifests"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let exitStatus = await IOSComposition.runEvaluation(
            IOSComposition.EvaluationRequest(model: ModelAssetID(rawValue: model)), folder: folder)

        let status = try JSONDecoder().decode(
            IOSComposition.EvaluationStatus.self,
            from: Data(contentsOf: folder.appendingPathComponent("status.json")))
        #expect(exitStatus == 1)
        #expect(status == IOSComposition.EvaluationStatus(status: "failed", reason: reason))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifests").path))
    }

    @Test func anUnknownModeFailsBeforeAnythingRuns() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-IOSEvaluation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var request = IOSComposition.EvaluationRequest(model: .whisperBase)
        request.mode = "fancy"

        #expect(await IOSComposition.runEvaluation(request, folder: folder) == 1)
        let status = try JSONDecoder().decode(
            IOSComposition.EvaluationStatus.self,
            from: Data(contentsOf: folder.appendingPathComponent("status.json")))
        #expect(status.reason == "evaluation.unknown-option")
    }

    @Test func leftoverWorkFromACrashedRunIsRemovedAndNothingElse() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-IOSEvaluationWork-\(UUID().uuidString)", isDirectory: true)
        let leftover = directory.appendingPathComponent("\(IOSComposition.workPrefix)crashed", isDirectory: true)
        let other = directory.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        IOSComposition.removeLeftoverWork(in: directory)

        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}
