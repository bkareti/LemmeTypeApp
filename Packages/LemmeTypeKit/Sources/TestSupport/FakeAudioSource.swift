import Domain
import Foundation
import Synchronization

/// Scriptable audio source: tests decide when buffers, device loss, or
/// interruptions happen. No hardware is touched.
public final class FakeAudioSource: AudioSource {
    private struct State {
        var onEvent: (@Sendable (AudioSourceEvent) -> Void)?
        var startError: AudioCaptureError?
        var fallsBack = false
        var startCount = 0
        var stopCount = 0
        var toneTask: Task<Void, Never>?
    }

    private let state = Mutex(State())
    private let liveTone: Bool

    /// - Parameters:
    ///   - startError: Error thrown by `start`, if any.
    ///   - fallsBack: Report that the system default was used instead of the chosen device.
    ///   - liveTone: Emit a quiet tone every 100 ms while running, for UI tests
    ///     that need a moving meter without a microphone.
    public init(startError: AudioCaptureError? = nil, fallsBack: Bool = false, liveTone: Bool = false) {
        self.liveTone = liveTone
        state.withLock {
            $0.startError = startError
            $0.fallsBack = fallsBack
        }
    }

    public var startCount: Int { state.withLock { $0.startCount } }
    public var stopCount: Int { state.withLock { $0.stopCount } }
    public var isRunning: Bool { state.withLock { $0.onEvent != nil } }

    public func start(
        input: AudioInputSelection,
        onEvent: @escaping @Sendable (AudioSourceEvent) -> Void
    ) throws(AudioCaptureError) -> AudioSourceStart {
        let result: Result<AudioSourceStart, AudioCaptureError> = state.withLock { state in
            if let error = state.startError { return .failure(error) }
            state.startCount += 1
            state.onEvent = onEvent
            return .success(AudioSourceStart(usedSystemDefaultFallback: state.fallsBack))
        }
        let started = try result.get()
        if liveTone {
            let task = Task.detached { [weak self] in
                while !Task.isCancelled, let self, self.isRunning {
                    self.emitTone(seconds: 0.1, amplitude: 0.3)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            state.withLock { $0.toneTask = task }
        }
        return started
    }

    public func stop() {
        let task = state.withLock { state -> Task<Void, Never>? in
            state.stopCount += 1
            state.onEvent = nil
            defer { state.toneTask = nil }
            return state.toneTask
        }
        task?.cancel()
    }

    /// Delivers an event if the source is running.
    public func emit(_ event: AudioSourceEvent) {
        state.withLock { $0.onEvent }?(event)
    }

    /// Delivers `seconds` of a sine tone in 100 ms buffers.
    public func emitTone(seconds: Double, sampleRate: Double = 48_000, amplitude: Float = 0.5) {
        let bufferFrames = Int(sampleRate / 10)
        let totalFrames = Int(seconds * sampleRate)
        var frame = 0
        while frame < totalFrames {
            let count = min(bufferFrames, totalFrames - frame)
            let samples = (0..<count).map { offset in
                amplitude * Float(sin(2 * Double.pi * 440 * Double(frame + offset) / sampleRate))
            }
            emit(.buffer(samples, sampleRate: sampleRate))
            frame += count
        }
    }
}
