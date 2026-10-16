import AVFoundation
import AppKit
import CoreAudio
import Domain
import Support

/// Microphone input through `AVAudioEngine`, delivering mono float buffers.
/// Selects a specific device through Core Audio, falling back to the system
/// default when it is missing, and reports device changes and sleep.
public final class AVAudioEngineSource: AudioSource, @unchecked Sendable {
    // `lock` guards `engine` and `observers`; start/stop are called from the
    // capture actor one at a time, and notifications only call `onEvent`.
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    public init() {}

    public func start(
        input: AudioInputSelection,
        onEvent: @escaping @Sendable (AudioSourceEvent) -> Void
    ) throws(AudioCaptureError) -> AudioSourceStart {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()

        let engine = AVAudioEngine()
        var usedFallback = false
        if case .device(let uid) = input {
            usedFallback = !Self.select(deviceUID: uid, on: engine)
        }

        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw .noInputDevice }

        Self.installMonoTap(on: node, format: format, onEvent: onEvent)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            node.removeTap(onBus: 0)
            throw .engineFailure(code: Int32(truncatingIfNeeded: (error as NSError).code))
        }

        observers = Self.observeInterruptions(of: engine, onEvent: onEvent)
        self.engine = engine
        return AudioSourceStart(usedSystemDefaultFallback: usedFallback)
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers = []
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// Downmixes every input buffer to mono and forwards it.
    private static func installMonoTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        onEvent: @escaping @Sendable (AudioSourceEvent) -> Void
    ) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: frameCount)
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for frame in 0..<frameCount {
                    mono[frame] += samples[frame]
                }
            }
            if channelCount > 1 {
                let scale = 1 / Float(channelCount)
                for frame in 0..<frameCount {
                    mono[frame] *= scale
                }
            }
            onEvent(.buffer(mono, sampleRate: buffer.format.sampleRate))
        }
    }

    /// Device/configuration changes end the session as device loss; sleep as an interruption.
    private static func observeInterruptions(
        of engine: AVAudioEngine,
        onEvent: @escaping @Sendable (AudioSourceEvent) -> Void
    ) -> [(NotificationCenter, any NSObjectProtocol)] {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        return [
            (
                center,
                center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
                    onEvent(.deviceLost)
                }
            ),
            (
                workspace,
                workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { _ in
                    onEvent(.interrupted)
                }
            ),
        ]
    }

    /// Points the engine's input at the Core Audio device with `uid`.
    private static func select(deviceUID uid: String, on engine: AVAudioEngine) -> Bool {
        guard var deviceID = deviceID(forUID: uid), let unit = engine.inputNode.audioUnit else { return false }
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        return status == noErr
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var cfUID = uid as CFString
        let status = withUnsafePointer(to: &cfUID) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPointer,
                &size,
                &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }
}
