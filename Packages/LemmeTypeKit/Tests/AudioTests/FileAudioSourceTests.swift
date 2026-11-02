import AVFoundation
import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio

/// The evaluation harness's audio: generated and transformed clips, and a
/// recorded clip played through the real capture service instead of a microphone.
struct FileAudioSourceTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-FileAudioSource-\(UUID().uuidString)", isDirectory: true)

    private func storage() -> AudioSessionStorage {
        AudioSessionStorage(directory: directory.appendingPathComponent("sessions", isDirectory: true))
    }

    private func collect(_ events: AsyncStream<AudioCaptureEvent>) -> Task<[AudioCaptureEvent], Never> {
        Task {
            var collected: [AudioCaptureEvent] = []
            for await event in events { collected.append(event) }
            return collected
        }
    }

    @Test func generatedClipsAreTheSameOnEveryRun() {
        #expect(
            AudioClip.whiteNoise(seconds: 0.5, amplitude: 0.1, seed: 7)
                == AudioClip.whiteNoise(seconds: 0.5, amplitude: 0.1, seed: 7))
        #expect(
            AudioClip.whiteNoise(seconds: 0.5, amplitude: 0.1, seed: 7)
                != AudioClip.whiteNoise(seconds: 0.5, amplitude: 0.1, seed: 8))
        let tone = AudioClip.tone(seconds: 1)
        #expect(tone.withNoise(snrDecibels: 10, seed: 7) == tone.withNoise(snrDecibels: 10, seed: 7))
        #expect(tone.samples.count == 16_000)
        #expect(AudioClip.silence(seconds: 0.25).samples.allSatisfy { $0 == 0 })
    }

    @Test func noiseLandsAtTheRequestedSignalToNoiseRatio() {
        let tone = AudioClip.tone(seconds: 2, amplitude: 0.5)
        let noisy = tone.withNoise(snrDecibels: 10, seed: 7)
        let signal = tone.samples.map { Double($0 * $0) }.reduce(0, +)
        let noise = zip(noisy.samples, tone.samples).map { Double(($0 - $1) * ($0 - $1)) }.reduce(0, +)
        let snr = 10 * log10(signal / noise)
        #expect(abs(snr - 10) < 0.5)
    }

    @Test func transformsClipPadTrimAndRepeat() {
        let tone = AudioClip.tone(seconds: 1, amplitude: 0.5)
        #expect(tone.clipped(gain: 4).samples.allSatisfy { abs($0) <= 1 })
        #expect(tone.clipped(gain: 4).samples.contains(1))
        #expect(abs(tone.padded(leading: 0.5, trailing: 1.5).duration - 3) < 0.001)
        #expect(abs(tone.prefix(seconds: 0.2).duration - 0.2) < 0.001)
        let repeated = tone.repeated(3, gap: 0.5)
        #expect(abs(repeated.duration - 4) < 0.001)
        #expect(tone.repeated(0).samples.isEmpty)
    }

    @Test func clipsSurviveAFileRoundTripInEitherContainer() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = AudioClip.whiteNoise(seconds: 0.5, amplitude: 0.2, seed: 3)
        for name in ["clip.caf", "clip.wav"] {
            let url = directory.appendingPathComponent(name)
            try clip.write(to: url)
            #expect(try AudioClip.load(from: url) == clip)
        }
        #expect(throws: AudioClip.FileError.unreadable) {
            try AudioClip.load(from: directory.appendingPathComponent("missing.wav"))
        }
    }

    @Test func stereoFilesAreMixedDownToMono() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stereo.caf")
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let channels = try #require(buffer.floatChannelData)
        for index in 0..<4 {
            channels[0][index] = 0.5
            channels[1][index] = -0.25
        }
        do {
            let file = try AVAudioFile(
                forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
        #expect(try AudioClip.load(from: url).samples == [0.125, 0.125, 0.125, 0.125])
    }

    @Test func aPlayedClipIsRecordedLikeLiveSpeech() async throws {
        let clip = AudioClip.tone(seconds: 1.5, sampleRate: 48_000)
        let source = FileAudioSource(clip: clip)
        let service = AudioCaptureService(
            source: source, storage: storage(), permissions: FakePermissions(statuses: [.microphone: .granted]))
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = collect(try await service.start(input: .systemDefault))

        source.play(upTo: 0.5)
        #expect(abs(source.playedSeconds - 0.5) < 0.001)
        #expect(!source.isFinished)
        source.play()
        #expect(source.isFinished)
        let recording = try await service.stop()
        let collected = await events.value

        #expect(source.startCount == 1)
        #expect(source.stopCount == 1)
        let recorded = try AudioClip.load(from: recording.fileURL)
        #expect(recorded.sampleRate == AudioCaptureFormat.speech.sampleRate)
        #expect(abs(recorded.duration - 1.5) < 0.05)
        #expect(abs(recording.duration - 1.5) < 0.05)
        #expect(collected.contains { if case .level(let level) = $0 { level > 0 } else { false } })
    }

    @Test func anInterruptionPartWayThroughEndsTheCaptureAndDeletesThePartialFile() async throws {
        let source = FileAudioSource(clip: AudioClip.tone(seconds: 3))
        let sessions = storage()
        let service = AudioCaptureService(
            source: source, storage: sessions, permissions: FakePermissions(statuses: [.microphone: .granted]))
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = collect(try await service.start(input: .systemDefault))

        source.play(upTo: 1)
        source.emit(.interrupted)
        let collected = await events.value

        #expect(collected.contains { if case .failed(.interrupted) = $0 { true } else { false } })
        let left = (try? FileManager.default.contentsOfDirectory(atPath: sessions.directory.path)) ?? []
        #expect(left.isEmpty)
        source.stop()
        source.play()
        #expect(!source.isFinished)  // nothing plays while stopped
    }
}
