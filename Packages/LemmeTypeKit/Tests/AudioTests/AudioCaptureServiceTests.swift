import AVFoundation
import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio

struct AudioCaptureServiceTests {
    private let source = FakeAudioSource()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioCaptureServiceTests-\(UUID().uuidString)", isDirectory: true))

    private func makeService(microphone: PermissionStatus = .granted) -> AudioCaptureService {
        AudioCaptureService(
            source: source,
            storage: storage,
            permissions: FakePermissions(statuses: [.microphone: microphone])
        )
    }

    private func sessionFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
    }

    /// Collects every event until the stream finishes.
    private func collect(_ events: AsyncStream<AudioCaptureEvent>) -> Task<[AudioCaptureEvent], Never> {
        Task {
            var collected: [AudioCaptureEvent] = []
            for await event in events { collected.append(event) }
            return collected
        }
    }

    @Test func refusesToStartWithoutMicrophonePermission() async {
        let service = makeService(microphone: .denied)

        await #expect(throws: AudioCaptureError.microphonePermissionMissing) {
            _ = try await service.start(input: .systemDefault)
        }
        #expect(source.startCount == 0)
        #expect(sessionFiles().isEmpty)
    }

    @Test func deliversSpeechFormatAudioAndWritesTheSessionFile() async throws {
        let service = makeService()
        let events = collect(try await service.start(input: .systemDefault))

        source.emitTone(seconds: 1, sampleRate: 48_000)
        let recording = try await service.stop()
        let collected = await events.value

        let chunks = collected.compactMap { if case .audio(let chunk) = $0 { chunk } else { nil } }
        #expect(!chunks.isEmpty)
        #expect(chunks.allSatisfy { $0.format == .speech })
        let samples = chunks.reduce(0) { $0 + $1.samples.count }
        #expect(abs(samples - 16_000) < 200, "got \(samples)")

        #expect(recording.format == .speech)
        #expect(abs(recording.duration - 1) < 0.02)
        let file = try AVAudioFile(forReading: recording.fileURL)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(file.fileFormat.channelCount == 1)
        #expect(file.length > 15_800)
        try FileManager.default.removeItem(at: recording.fileURL)
    }

    @Test func reportsLevelsForAMeter() async throws {
        let service = makeService()
        let events = collect(try await service.start(input: .systemDefault))

        source.emitTone(seconds: 0.3, amplitude: 0.5)
        source.emit(.buffer([Float](repeating: 0, count: 4800), sampleRate: 48_000))
        let recording = try await service.stop()
        let levels = await events.value.compactMap { if case .level(let level) = $0 { level } else { nil } }

        #expect(levels.count == 4)
        #expect(levels.dropLast().allSatisfy { $0 > 0.7 && $0 <= 1 })
        #expect(levels.last == 0)
        try FileManager.default.removeItem(at: recording.fileURL)
    }

    @Test func cancelStopsCaptureAndDeletesTheRecording() async throws {
        let service = makeService()
        let events = collect(try await service.start(input: .systemDefault))
        source.emitTone(seconds: 0.5)

        await service.cancel()
        _ = await events.value

        #expect(!source.isRunning)
        #expect(sessionFiles().isEmpty)
        await #expect(throws: AudioCaptureError.notCapturing) { _ = try await service.stop() }
    }

    @Test func deviceLossStopsSafelyWithARecoverableError() async throws {
        let service = makeService()
        let events = collect(try await service.start(input: .device(id: "usb-mic")))
        source.emitTone(seconds: 0.2)

        source.emit(.deviceLost)
        let collected = await events.value

        guard case .failed(let error) = collected.last else {
            Issue.record("Expected a failure event")
            return
        }
        #expect(error == .deviceDisconnected)
        #expect(!source.isRunning)
        #expect(sessionFiles().isEmpty)
        await #expect(throws: AudioCaptureError.deviceDisconnected) { _ = try await service.stop() }
    }

    @Test func interruptionStopsSafely() async throws {
        let service = makeService()
        let events = collect(try await service.start(input: .systemDefault))

        source.emit(.interrupted)
        let collected = await events.value

        guard case .failed(.interrupted) = collected.last else {
            Issue.record("Expected an interruption failure")
            return
        }
        #expect(sessionFiles().isEmpty)
    }

    @Test func canStartAgainAfterAFailure() async throws {
        let service = makeService()
        let first = collect(try await service.start(input: .systemDefault))
        source.emit(.deviceLost)
        _ = await first.value

        let second = collect(try await service.start(input: .systemDefault))
        source.emitTone(seconds: 0.1)
        let recording = try await service.stop()
        _ = await second.value

        #expect(source.startCount == 2)
        try FileManager.default.removeItem(at: recording.fileURL)
    }

    @Test func unavailableDeviceFallsBackToSystemDefault() async throws {
        let source = FakeAudioSource(fallsBack: true)
        let service = AudioCaptureService(
            source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: .granted]))
        let events = collect(try await service.start(input: .device(id: "gone")))

        await service.cancel()
        let collected = await events.value

        guard case .fellBackToSystemDefault = collected.first else {
            Issue.record("Expected a fallback event first")
            return
        }
    }

    @Test func sourceFailureIsReportedAndLeavesNoFile() async {
        let source = FakeAudioSource(startError: .noInputDevice)
        let service = AudioCaptureService(
            source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: .granted]))

        await #expect(throws: AudioCaptureError.noInputDevice) { _ = try await service.start(input: .systemDefault) }
        #expect(sessionFiles().isEmpty)
    }

    @Test func onlyOneSessionAtATime() async throws {
        let service = makeService()
        _ = try await service.start(input: .systemDefault)

        await #expect(throws: AudioCaptureError.alreadyCapturing) { _ = try await service.start(input: .systemDefault) }
        await service.cancel()
    }

    @Test func recordingsAreOwnerOnly() async throws {
        let service = makeService()
        _ = try await service.start(input: .systemDefault)
        let file = try #require(sessionFiles().first)

        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        let directoryMode =
            try FileManager.default.attributesOfItem(atPath: storage.directory.path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(directoryMode == 0o700)
        await service.cancel()
    }

    @Test func purgeRemovesLeftoverRecordings() async throws {
        let service = makeService()
        _ = try await service.start(input: .systemDefault)
        #expect(sessionFiles().count == 1)

        await service.purgeLeftovers()

        #expect(sessionFiles().isEmpty)
        await service.cancel()
    }
}

struct SpeechResamplerTests {
    @Test(arguments: [16_000.0, 44_100, 48_000])
    func producesSixteenKilohertzAcrossBuffers(inputRate: Double) throws {
        let resampler = try SpeechResampler(inputSampleRate: inputRate)
        let buffer = [Float](repeating: 0.25, count: Int(inputRate / 10))

        let total = (0..<10).reduce(0) { sum, _ in sum + resampler.process(buffer).count } + resampler.flush().count

        #expect(abs(total - 16_000) < 200, "got \(total)")
    }
}

struct AudioLevelMeterTests {
    @Test func mapsSilenceAndFullScale() {
        #expect(AudioLevelMeter.level(of: []) == 0)
        #expect(AudioLevelMeter.level(of: [0, 0, 0]) == 0)
        #expect(AudioLevelMeter.level(of: [1, -1, 1, -1]) == 1)
        #expect(AudioLevelMeter.level(of: [Float](repeating: 0.001, count: 10)) == 0)  // −60 dBFS
    }
}
