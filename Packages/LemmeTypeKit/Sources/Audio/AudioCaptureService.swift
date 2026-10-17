import Domain
import Foundation
import Support

/// Runs one capture session at a time: checks permission, starts the source,
/// resamples to the speech format, writes the protected session file, meters
/// levels, and handles stop, cancel, device loss, and interruption.
///
/// Raw samples and levels are never logged.
public actor AudioCaptureService: AudioCapturing {
    private struct Session {
        let writer: AudioSessionWriter
        let events: AsyncStream<AudioCaptureEvent>.Continuation
        let sourceEvents: AsyncStream<AudioSourceEvent>.Continuation
        var pump: Task<Void, Never>?
        var resampler: SpeechResampler?
    }

    private let source: any AudioSource
    private let storage: AudioSessionStorage
    private let permissions: any PermissionChecking
    private let diagnostics: any DiagnosticsRecording
    private let freeSpace: @Sendable (URL) -> Int64?
    private var session: Session?
    private var failure: AudioCaptureError?

    public init(
        source: any AudioSource,
        storage: AudioSessionStorage,
        permissions: any PermissionChecking,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics(),
        freeSpace: @escaping @Sendable (URL) -> Int64? = AudioCaptureService.volumeFreeSpace
    ) {
        self.freeSpace = freeSpace
        self.source = source
        self.storage = storage
        self.permissions = permissions
        self.diagnostics = diagnostics
    }

    /// Free space for important data on the volume holding `url` (or its
    /// nearest existing parent); `nil` when it can't be read.
    public static let volumeFreeSpace: @Sendable (URL) -> Int64? = { url in
        var candidate = url
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.pathComponents.count > 1 {
            candidate.deleteLastPathComponent()
        }
        let values = try? candidate.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public func start(input: AudioInputSelection) throws(AudioCaptureError) -> AsyncStream<AudioCaptureEvent> {
        guard session == nil else { throw .alreadyCapturing }
        guard permissions.status(for: .microphone) == .granted else {
            diagnostics.record(
                .audio, "capture.start-failed", ["error": .id(AudioCaptureError.microphonePermissionMissing.identifier)]
            )
            throw .microphonePermissionMissing
        }
        // Refuse before the microphone starts rather than fail mid-sentence (E5-S6).
        if let available = freeSpace(storage.directory), available < AudioCaptureError.minimumFreeBytes {
            diagnostics.record(
                .audio, "capture.start-failed", ["error": .id(AudioCaptureError.insufficientStorage.identifier)])
            throw .insufficientStorage
        }

        let writer = try storage.makeWriter()
        let (events, eventContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
        let (sourceEvents, sourceContinuation) = AsyncStream.makeStream(of: AudioSourceEvent.self)

        let started: AudioSourceStart
        do {
            started = try source.start(input: input) { sourceContinuation.yield($0) }
        } catch {
            writer.discard()
            sourceContinuation.finish()
            eventContinuation.finish()
            Log.audio.error("Capture failed to start: \(error.identifier, privacy: .public)")
            diagnostics.record(.audio, "capture.start-failed", ["error": .id(error.identifier)])
            throw error
        }

        failure = nil
        session = Session(writer: writer, events: eventContinuation, sourceEvents: sourceContinuation)
        session?.pump = Task {
            for await event in sourceEvents {
                self.process(event)
            }
        }
        if started.usedSystemDefaultFallback {
            eventContinuation.yield(.fellBackToSystemDefault)
        }
        Log.audio.info("Capture started; fallback=\(started.usedSystemDefaultFallback, privacy: .public)")
        diagnostics.record(
            .audio, "capture.started",
            [
                "input": .id(input == .systemDefault ? "system-default" : "specific-device"),
                "fallback": .flag(started.usedSystemDefaultFallback),
            ])
        return events
    }

    public func stop() async throws(AudioCaptureError) -> RecordedAudio {
        guard let current = session else { throw failure ?? .notCapturing }
        source.stop()
        current.sourceEvents.finish()
        await current.pump?.value  // drain buffers already delivered

        guard let finished = session else { throw failure ?? .notCapturing }
        session = nil
        if let tail = finished.resampler?.flush(), !tail.isEmpty {
            do {
                try finished.writer.append(tail)
            } catch {
                finished.writer.discard()
                finished.events.yield(.failed(error))
                finished.events.finish()
                throw error
            }
            finished.events.yield(.audio(AudioChunk(samples: tail)))
        }
        let recording = finished.writer.finish()
        finished.events.finish()
        Log.audio.info("Capture stopped after \(recording.duration, format: .fixed(precision: 1), privacy: .public)s")
        diagnostics.record(.audio, "capture.stopped", ["seconds": .seconds(recording.duration)])
        return recording
    }

    public func cancel() async {
        guard let current = session else { return }
        session = nil
        source.stop()
        current.sourceEvents.finish()
        current.pump?.cancel()
        await current.pump?.value
        current.writer.discard()
        current.events.finish()
        Log.audio.info("Capture cancelled; recording deleted")
        diagnostics.record(.audio, "capture.cancelled")
    }

    public func purgeLeftovers() {
        storage.purgeAll()
    }

    private func process(_ event: AudioSourceEvent) {
        guard session != nil else { return }
        switch event {
        case .buffer(let samples, let sampleRate):
            do {
                let speech = try resampler(for: sampleRate).process(samples)
                try session?.writer.append(speech)
                session?.events.yield(.audio(AudioChunk(samples: speech)))
                session?.events.yield(.level(AudioLevelMeter.level(of: samples)))
            } catch {
                fail(with: error)
            }
        case .deviceLost:
            fail(with: .deviceDisconnected)
        case .interrupted:
            fail(with: .interrupted)
        }
    }

    private func resampler(for sampleRate: Double) throws(AudioCaptureError) -> SpeechResampler {
        if let existing = session?.resampler, existing.inputSampleRate == sampleRate {
            return existing
        }
        let resampler = try SpeechResampler(inputSampleRate: sampleRate)
        session?.resampler = resampler
        return resampler
    }

    /// Stops safely, deletes the partial recording, and reports a recoverable error.
    private func fail(with error: AudioCaptureError) {
        guard let current = session else { return }
        session = nil
        failure = error
        source.stop()
        current.sourceEvents.finish()
        current.writer.discard()
        current.events.yield(.failed(error))
        current.events.finish()
        Log.audio.error("Capture failed: \(error.identifier, privacy: .public)")
        diagnostics.record(.audio, "capture.failed", ["error": .id(error.identifier)])
    }
}
