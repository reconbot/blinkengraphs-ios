import BlinkengraphsCore
import Darwin
import Foundation

typealias ProbeOutcome = Measurements.Outcome

/// A send that fails because no route exists for the Target's IP version.
func noRoute(_ e: Int32) -> Bool { e == ENETUNREACH || e == EAFNOSUPPORT || e == EADDRNOTAVAIL }

protocol ProbeRunner: Sendable {
    func handles(_ probe: Probe) -> Bool
    /// `address` is the Target resolved to an address (the Gateway's, for `gateway`). A non-zero
    /// `interface` pins the Probe to that Link's interface.
    func run(_ probe: Probe, address: String, interface: UInt32, timeout: Duration) async -> ProbeOutcome
}

/// Runs blocking socket work off the cooperative pool, which must not block.
func offPool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .utility).async { cont.resume(returning: work()) }
    }
}

struct ICMPProbeRunner: ProbeRunner {
    func handles(_ probe: Probe) -> Bool { probe.protocol == "icmp" }

    func run(_ probe: Probe, address: String, interface: UInt32, timeout: Duration) async -> ProbeOutcome {
        switch await offPool({ Sockets.echo(to: address, interface: interface, timeout: timeout) }) {
        case .reply(_, .echoReply, let ms): return .reply(ms: ms)
        // Local Network Privacy gates TCP and UDP, not ICMP: a device test pinged the Gateway
        // with no prompt (docs/research/local-network-privacy.md). A failed send is a loss.
        case .sendFailed(let e) where noRoute(e): return .unreachable
        case .reply, .timeout, .sendFailed: return .lost
        }
    }
}

/// DNS Probes to a named server. The `system-dns` Target needs the system resolver's address,
/// which this runner doesn't know yet.
struct DNSProbeRunner: ProbeRunner {
    let queryName: String

    func handles(_ probe: Probe) -> Bool { probe.protocol == "dns" && probe.target != Probe.systemDNS }

    func run(_ probe: Probe, address: String, interface: UInt32, timeout: Duration) async -> ProbeOutcome {
        let name = queryName
        switch await offPool({ Sockets.dnsQuery(name, server: address, interface: interface, timeout: timeout) }) {
        case .answer(let ms): return .reply(ms: ms)
        case .timeout: return .lost
        // UDP to a LAN address is gated (TN3179), but Apple names no errno for a denied send;
        // EHOSTUNREACH and EPERM are the assumption, and only the Gateway is on the LAN.
        case .sendFailed(let e) where noRoute(e): return .unreachable
        case .sendFailed(let e):
            return probe.target == Probe.gateway && (e == EHOSTUNREACH || e == EPERM) ? .denied : .lost
        }
    }
}

/// TCP handshake time over a BSD socket.
struct TCPProbeRunner: ProbeRunner {
    func handles(_ probe: Probe) -> Bool { probe.protocol.hasPrefix("tcp:") }

    func run(_ probe: Probe, address: String, interface: UInt32, timeout: Duration) async -> ProbeOutcome {
        guard let port = UInt16(probe.protocol.dropFirst(4)) else { return .lost }
        switch await offPool({ Sockets.tcpConnect(to: address, port: port, interface: interface, timeout: timeout) }) {
        case .connected(let ms): return .reply(ms: ms)
        case .failed(let e) where noRoute(e): return .unreachable
        case .timeout, .failed: return .lost
        }
    }
}
