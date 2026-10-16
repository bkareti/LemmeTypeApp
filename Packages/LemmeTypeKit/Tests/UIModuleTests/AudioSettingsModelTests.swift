import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

@MainActor
struct AudioSettingsModelTests {
    private let usb = AudioInputDevice(id: "usb", name: "USB Mic", isSystemDefault: false)
    private let builtIn = AudioInputDevice(id: "built-in", name: "MacBook Microphone", isSystemDefault: true)
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioSettingsModelTests-\(UUID().uuidString)", isDirectory: true))

    private func makeModel(
        source: FakeAudioSource = FakeAudioSource(),
        microphone: PermissionStatus = .granted,
        preferences: FakePreferences = FakePreferences()
    ) -> AudioSettingsModel {
        AudioSettingsModel(
            capture: AudioCaptureService(
                source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: microphone])),
            deviceLister: FakeAudioDeviceLister(devices: [builtIn, usb]),
            preferences: preferences
        )
    }

    @Test func listsDevicesAndPersistsTheSelection() {
        let preferences = FakePreferences()
        let model = makeModel(preferences: preferences)

        model.select(.device(id: "usb"))

        #expect(model.devices == [builtIn, usb])
        #expect(preferences.audioInput == .device(id: "usb"))
        #expect(!model.isSelectedDeviceMissing)
    }

    @Test func missingSavedDeviceExplainsTheFallback() {
        let model = makeModel(preferences: FakePreferences(audioInput: .device(id: "gone")))

        #expect(model.isSelectedDeviceMissing)
        #expect(model.notice != nil)
    }

    @Test func testShowsLevelsAndKeepsNothing() async throws {
        let source = FakeAudioSource()
        let model = makeModel(source: source)

        await model.startTest()
        #expect(model.isTesting)
        source.emitTone(seconds: 0.2, amplitude: 0.5)
        try await waitUntil { model.level > 0.5 }

        await model.stopTest()

        #expect(!model.isTesting)
        #expect(model.level == 0)
        let files = try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)
        #expect(files?.isEmpty ?? true)
    }

    @Test func testWithoutPermissionExplainsWhatToDo() async {
        let model = makeModel(microphone: .denied)

        await model.startTest()

        #expect(!model.isTesting)
        #expect(model.notice == AudioSettingsModel.message(for: .microphonePermissionMissing))
    }

    @Test func disconnectDuringTestEndsItWithARecoverableMessage() async throws {
        let source = FakeAudioSource()
        let model = makeModel(source: source)
        await model.startTest()

        source.emit(.deviceLost)
        try await waitUntil { !model.isTesting }

        #expect(model.notice == AudioSettingsModel.message(for: .deviceDisconnected))
    }

    @Test func everyCaptureErrorHasAMessage() {
        let errors: [AudioCaptureError] = [
            .microphonePermissionMissing, .noInputDevice, .deviceDisconnected, .interrupted, .engineFailure(code: 1),
            .storageFailure,
        ]
        #expect(errors.allSatisfy { !AudioSettingsModel.message(for: $0).isEmpty })
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
