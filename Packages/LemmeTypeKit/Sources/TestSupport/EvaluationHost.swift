#if DEBUG
    import Darwin
    import Foundation

    /// What a report says about the device it ran on, on macOS and iOS alike.
    enum EvaluationHost {
        /// Highest resident memory of this process so far, in bytes (Darwin reports bytes).
        static func peakResidentBytes() -> Int {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return usage.ru_maxrss
        }

        /// `Mac15,6` on a Mac, `iPhone17,1` on an iPhone: the machine identifier, never a name.
        /// The Simulator reports the device it imitates with a `simulator-` prefix, so its
        /// timings are never read as a device's.
        static func hardwareModel() -> String {
            #if targetEnvironment(simulator)
                if let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
                    return "simulator-\(model)"
                }
            #endif
            #if os(macOS)
                let key = "hw.model"
            #else
                let key = "hw.machine"
            #endif
            var size = 0
            sysctlbyname(key, nil, &size, nil, 0)
            var model = [CChar](repeating: 0, count: max(size, 1))
            sysctlbyname(key, &model, &size, nil, 0)
            return String(bytes: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? "unknown"
        }

        static var operatingSystem: String { ProcessInfo.processInfo.operatingSystemVersionString }
        static var physicalMemoryGB: Int { Int(ProcessInfo.processInfo.physicalMemory >> 30) }
    }
#endif
