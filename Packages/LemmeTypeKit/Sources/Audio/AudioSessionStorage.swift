import AVFoundation
import Domain
import Support

/// Where session recordings live: an app-private temporary directory (0700)
/// with one file (0600) per session. Files are deleted on cancel and failure,
/// by the consumer after transcription, and at launch for anything left over.
public struct AudioSessionStorage: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func makeDefault() -> AudioSessionStorage {
        AudioSessionStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LemmeType", isDirectory: true)
                .appendingPathComponent("Sessions", isDirectory: true))
    }

    func makeWriter() throws(AudioCaptureError) -> AudioSessionWriter {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
            return try AudioSessionWriter(url: url)
        } catch {
            Log.audio.error("Could not create session recording")
            throw .storageFailure
        }
    }

    /// Deletes every leftover recording.
    public func purgeAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        if !files.isEmpty {
            Log.audio.info("Purged \(files.count, privacy: .public) leftover recordings")
        }
    }
}

/// Appends speech-format samples to one session file.
final class AudioSessionWriter {
    let url: URL
    private var file: AVAudioFile?
    private let format: AVAudioFormat
    private(set) var frameCount: AVAudioFramePosition = 0

    init(url: URL) throws {
        let speech = AudioCaptureFormat.speech
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: speech.sampleRate,
                channels: AVAudioChannelCount(speech.channelCount), interleaved: false)
        else { throw AudioCaptureError.storageFailure }
        self.url = url
        self.format = format
        self.file = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func append(_ samples: [Float]) throws(AudioCaptureError) {
        guard let file, !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else { throw .storageFailure }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        do {
            try file.write(from: buffer)
        } catch {
            throw .storageFailure
        }
        frameCount += AVAudioFramePosition(samples.count)
    }

    /// Closes the file and describes it.
    func finish() -> RecordedAudio {
        file = nil
        return RecordedAudio(
            fileURL: url,
            duration: Double(frameCount) / AudioCaptureFormat.speech.sampleRate,
            format: .speech
        )
    }

    /// Closes and deletes the file.
    func discard() {
        file = nil
        try? FileManager.default.removeItem(at: url)
    }
}
