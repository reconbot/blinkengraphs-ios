import BlinkengraphsCore
import Darwin
import Foundation
import Network

enum ProbeOutcome: Sendable {
    case reply(ms: Double)
    case lost
    /// The OS refused to send it, e.g. Local Network Privacy. Not a loss.
    case denied
}

protocol ProbeRunner: Sendable {
    func handles(_ probe: Probe) -> Bool
    /// `address` is the Target resolved to an IPv4 address (the Gateway's, for `gateway`).
    func run(_ probe: Probe, address: String, timeout: Duration) async -> ProbeOutcome
}

/// Runs blocking socket work off the cooperative pool, which must not block.
func offPool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .utility).async { cont.resume(returning: work()) }
    }
}

struct ICMPProbeRunner: ProbeRunner {
    func handles(_ probe: Probe) -> Bool { probe.protocol == "icmp" }

    func run(_ probe: Probe, address: String, timeout: Duration) async -> ProbeOutcome {
        switch await offPool({ Sockets.echo(to: address, timeout: timeout) }) {
        case .reply(_, .echoReply, let ms): return .reply(ms: ms)
        // Local Network Privacy gates TCP and UDP, not ICMP: a device test pinged the Gateway
        // with no prompt (docs/research/local-network-privacy.md). A failed send is a loss.
        case .reply, .timeout, .sendFailed: return .lost
        }
    }
}

/// DNS Probes to a named server. The `system-dns` Target needs the system resolver's address,
/// which this runner doesn't know yet.
struct DNSProbeRunner: ProbeRunner {
    let queryName: String

    func handles(_ probe: Probe) -> Bool { probe.protocol == "dns" && probe.target != Probe.systemDNS }

    func run(_ probe: Probe, address: String, timeout: Duration) async -> ProbeOutcome {
        let name = queryName
        switch await offPool({ Sockets.dnsQuery(name, server: address, timeout: timeout) }) {
        case .answer(let ms): return .reply(ms: ms)
        case .timeout: return .lost
        // UDP to a LAN address is gated (TN3179), but Apple names no errno for a denied send;
        // EHOSTUNREACH and EPERM are the assumption, and only the Gateway is on the LAN.
        case .sendFailed(let e):
            return probe.target == Probe.gateway && (e == EHOSTUNREACH || e == EPERM) ? .denied : .lost
        }
    }
}

/// TCP handshake time via Network.framework.
struct TCPProbeRunner: ProbeRunner {
    func handles(_ probe: Probe) -> Bool { probe.protocol.hasPrefix("tcp:") }

    func run(_ probe: Probe, address: String, timeout: Duration) async -> ProbeOutcome {
        guard let port = NWEndpoint.Port(String(probe.protocol.dropFirst(4))) else { return .lost }
        let params = NWParameters.tcp
        params.preferNoProxies = true
        let conn = NWConnection(host: NWEndpoint.Host(address), port: port, using: params)
        let start = ContinuousClock.now
        let once = Once()

        return await withCheckedContinuation { cont in
            @Sendable func finish(_ outcome: ProbeOutcome) {
                guard once.claim() else { return }
                conn.cancel()
                cont.resume(returning: outcome)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.reply(ms: (ContinuousClock.now - start).milliseconds))
                case .waiting, .failed:
                    finish(conn.currentPath?.unsatisfiedReason == .localNetworkDenied ? .denied : .lost)
                default: break
                }
            }
            conn.start(queue: .global(qos: .utility))
            Task {
                try? await Task.sleep(for: timeout)
                finish(.lost)
            }
        }
    }
}

/// Thread-safe one-shot latch for continuation callbacks that can race.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}
