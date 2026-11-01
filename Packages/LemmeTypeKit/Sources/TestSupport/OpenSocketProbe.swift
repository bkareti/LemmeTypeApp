import Darwin
import Foundation
import Synchronization

/// Lists the internet (IPv4 and IPv6) sockets a process has open, from the
/// kernel's file-descriptor table via libproc (E6-S2). No subprocess, no root.
///
/// Local-domain sockets (XPC, the window server) are ignored. A socket that is
/// opened and closed between two samples can be missed, so `SocketWatch`
/// samples often and the manual check (MA-31) uses a real network monitor.
public enum OpenSocketProbe {
    /// One open internet socket, described without any address data.
    public struct Socket: Hashable, Sendable, CustomStringConvertible {
        public let descriptor: Int32
        public let isIPv6: Bool
        /// 1 = stream (TCP), 2 = datagram (UDP), others as reported.
        public let type: Int32

        public var description: String {
            "fd \(descriptor) \(isIPv6 ? "IPv6" : "IPv4") \(type == 1 ? "stream" : type == 2 ? "datagram" : "type \(type)")"
        }
    }

    /// The internet sockets `pid` has open right now (this process by default).
    public static func internetSockets(pid: Int32 = getpid()) -> [Socket] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let capacity = Int(size) / MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, size)
        guard bytes > 0 else { return [] }

        var sockets: [Socket] = []
        for descriptor in descriptors.prefix(Int(bytes) / MemoryLayout<proc_fdinfo>.stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let expected = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, expected) == expected else {
                continue
            }
            let family = info.psi.soi_family
            guard family == AF_INET || family == AF_INET6 else { continue }
            sockets.append(
                Socket(descriptor: descriptor.proc_fd, isIPv6: family == AF_INET6, type: info.psi.soi_type))
        }
        return sockets
    }
}

/// Watches this process for internet sockets that were not open when it started.
///
/// Create it before the work, call ``stop()`` after. It samples every few
/// milliseconds on a background task and once more at the end, so a socket
/// that stays open (or is open at any sample) is reported.
public final class SocketWatch: Sendable {
    /// Shared with the sampling task; a class because a `Mutex` cannot be copied.
    private final class Sightings: Sendable {
        let seen = Mutex<Set<OpenSocketProbe.Socket>>([])
    }

    private let baseline: Set<OpenSocketProbe.Socket>
    private let sightings: Sightings
    private let task: Task<Void, Never>

    public init(interval: Duration = .milliseconds(2)) {
        let baseline = Set(OpenSocketProbe.internetSockets())
        let sightings = Sightings()
        self.baseline = baseline
        self.sightings = sightings
        task = Task.detached {
            while !Task.isCancelled {
                let current = Set(OpenSocketProbe.internetSockets()).subtracting(baseline)
                if !current.isEmpty { sightings.seen.withLock { $0.formUnion(current) } }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Stops sampling and returns every new internet socket seen.
    @discardableResult
    public func stop() -> [OpenSocketProbe.Socket] {
        task.cancel()
        let last = Set(OpenSocketProbe.internetSockets()).subtracting(baseline)
        sightings.seen.withLock { $0.formUnion(last) }
        return sightings.seen.withLock { $0 }.sorted { $0.descriptor < $1.descriptor }
    }
}
