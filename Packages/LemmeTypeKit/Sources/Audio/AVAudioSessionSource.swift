#if os(iOS)
    import AVFoundation
    import Domain
    import Support

    /// Microphone input on iPhone and iPad (ADR 0027): an `AVAudioSession` used
    /// only for recording, and the same mono tap as the Mac. The session is
    /// deactivated the moment capture stops, so LemmeType never holds the
    /// microphone while the user is not dictating.
    ///
    /// iOS has one input route chosen by the system, so a specific device is never
    /// selected; asking for one reports a fallback to the system default.
    public final class AVAudioSessionSource: AudioSource, @unchecked Sendable {
        // `lock` guards `engine` and `observers`; start/stop are called from the
        // capture actor one at a time, and notifications only call `onEvent`.
        private let lock = NSLock()
        private var engine: AVAudioEngine?
        private var observers: [any NSObjectProtocol] = []

        public init() {}

        public func start(
            input: AudioInputSelection,
            onEvent: @escaping @Sendable (AudioSourceEvent) -> Void
        ) throws(AudioCaptureError) -> AudioSourceStart {
            lock.lock()
            defer { lock.unlock() }
            stopLocked()

            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.record, mode: .default, options: [])
                try session.setActive(true)
            } catch {
                throw .engineFailure(code: Int32(truncatingIfNeeded: (error as NSError).code))
            }
            guard session.isInputAvailable else {
                Self.deactivate(session)
                throw .noInputDevice
            }

            let engine = AVAudioEngine()
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                Self.deactivate(session)
                throw .noInputDevice
            }

            MonoInputTap.install(on: node, format: format, onEvent: onEvent)
            engine.prepare()
            do {
                try engine.start()
            } catch {
                node.removeTap(onBus: 0)
                Self.deactivate(session)
                throw .engineFailure(code: Int32(truncatingIfNeeded: (error as NSError).code))
            }

            observers = Self.observe(engine: engine, onEvent: onEvent)
            self.engine = engine
            return AudioSourceStart(usedSystemDefaultFallback: input != .systemDefault)
        }

        public func stop() {
            lock.lock()
            defer { lock.unlock() }
            stopLocked()
        }

        private func stopLocked() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
            guard let engine else { return }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
            Self.deactivate(AVAudioSession.sharedInstance())
        }

        private static func deactivate(_ session: AVAudioSession) {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }

        /// A call, Siri, or an alarm taking the input is an interruption; losing
        /// the headset or a route change the engine cannot follow is device loss.
        private static func observe(
            engine: AVAudioEngine,
            onEvent: @escaping @Sendable (AudioSourceEvent) -> Void
        ) -> [any NSObjectProtocol] {
            let center = NotificationCenter.default
            return [
                center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { note in
                    let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                    if raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began {
                        onEvent(.interrupted)
                    }
                },
                center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { note in
                    let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                    if raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .oldDeviceUnavailable {
                        onEvent(.deviceLost)
                    }
                },
                center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
                    onEvent(.deviceLost)
                },
                center.addObserver(
                    forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil,
                    using: { _ in onEvent(.interrupted) }),
            ]
        }
    }
#endif
