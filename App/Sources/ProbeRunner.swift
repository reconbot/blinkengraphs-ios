import BlinkengraphsCore
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
    func run(_ probe: Probe, timeout: Duration) async -> ProbeOutcome
}

/// TCP handshake time via Network.framework. ICMP, DNS and the Gateway come next.
struct TCPProbeRunner: ProbeRunner {
    func handles(_ probe: Probe) -> Bool {
        probe.protocol.hasPrefix("tcp:") && probe.target != Probe.gateway && probe.target != Probe.systemDNS
    }

    func run(_ probe: Probe, timeout: Duration) async -> ProbeOutcome {
        guard let port = NWEndpoint.Port(String(probe.protocol.dropFirst(4))) else { return .lost }
        let params = NWParameters.tcp
        params.preferNoProxies = true
        let conn = NWConnection(host: NWEndpoint.Host(probe.target), port: port, using: params)
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
                    let d = ContinuousClock.now - start
                    finish(.reply(ms: Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15))
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
