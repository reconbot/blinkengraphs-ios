import BlinkengraphsCore
import Darwin
import Foundation
import Synchronization

/// Blocking BSD-socket Probes. Callers run them off the main actor.
///
/// Datagram ICMP sockets need no privilege on Darwin; a hosted macOS runner showed echo and
/// TTL-limited echo both work as an ordinary user (.github/diagnostics/net-probe.swift).
enum Sockets {
    enum EchoOutcome: Sendable {
        case reply(from: String, kind: ICMP.Reply.Kind, ms: Double)
        case timeout
        case sendFailed(errno: Int32)
    }

    private static let nextSequence = Mutex<UInt16>(0)

    private static func sequence() -> UInt16 {
        nextSequence.withLock { $0 &+= 1; return $0 }
    }

    /// One echo request to `ip`. With `ttl`, a router on the way may answer with time exceeded.
    static func echo(to ip: String, ttl: Int32? = nil, timeout: Duration) -> EchoOutcome {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return .sendFailed(errno: errno) }
        defer { close(fd) }
        if var t = ttl { setsockopt(fd, IPPROTO_IP, IP_TTL, &t, socklen_t(MemoryLayout<Int32>.size)) }

        let seq = sequence()
        let packet = ICMP.echoRequest(identifier: UInt16(truncatingIfNeeded: getpid()), sequence: seq,
                                      payload: Array("blinkengraphs".utf8))
        let start = ContinuousClock.now
        guard send(fd, packet, to: ip, port: 0) else { return .sendFailed(errno: errno) }

        // Every datagram ICMP socket may see every reply, so match on our sequence.
        while let (bytes, from) = receive(fd, until: start + timeout) {
            guard let reply = ICMP.parse(bytes, includesIPHeader: true), reply.sequence == seq else { continue }
            if reply.kind == .echoReply && from != ip { continue }
            return .reply(from: from, kind: reply.kind, ms: (ContinuousClock.now - start).milliseconds)
        }
        return .timeout
    }

    enum DNSOutcome: Sendable {
        case answer(ms: Double)
        case timeout
        case sendFailed(errno: Int32)
    }

    /// One A query for `name` straight to `server`, so the OS resolver cache doesn't hide its latency.
    static func dnsQuery(_ name: String, server: String, timeout: Duration) -> DNSOutcome {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return .sendFailed(errno: errno) }
        defer { close(fd) }
        let id = UInt16.random(in: .min ... .max)
        let start = ContinuousClock.now
        guard send(fd, DNS.query(id: id, name: name), to: server, port: 53) else { return .sendFailed(errno: errno) }
        while let (bytes, from) = receive(fd, until: start + timeout) {
            if from == server, DNS.parseResponse(bytes, id: id) != nil {
                return .answer(ms: (ContinuousClock.now - start).milliseconds)
            }
        }
        return .timeout
    }

    private static func send(_ fd: Int32, _ bytes: [UInt8], to ip: String, port: UInt16) -> Bool {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &a.sin_addr) == 1 else { return false }
        return withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        } == bytes.count
    }

    /// The next datagram before `deadline`, with its source address; nil once the deadline passes.
    private static func receive(_ fd: Int32, until deadline: ContinuousClock.Instant) -> ([UInt8], String)? {
        while true {
            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero else { return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32(max(1, remaining.milliseconds.rounded(.up))))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { return nil }

            var buf = [UInt8](repeating: 0, count: 1500)
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
            }
            guard n > 0 else { continue }
            var s = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &s, socklen_t(INET_ADDRSTRLEN))
            return (Array(buf.prefix(n)), String(cString: s))
        }
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
