import BlinkengraphsCore
import Darwin
import Foundation
import Synchronization

/// Blocking BSD-socket Probes over IPv4 or IPv6, chosen by the address literal.
/// Callers run them off the main actor.
///
/// Datagram ICMP and ICMPv6 sockets need no privilege on Darwin. BSD sockets also go through
/// iOS's 464XLAT on IPv6-only cellular, where IPv4 traffic is translated
/// (docs/research/ipv6-only-cellular.md).
enum Sockets {
    enum EchoOutcome: Sendable {
        case reply(from: String, kind: ICMP.Reply.Kind, ms: Double)
        case timeout
        case sendFailed(errno: Int32)
    }

    enum DNSOutcome: Sendable {
        case answer(ms: Double)
        case timeout
        case sendFailed(errno: Int32)
    }

    enum ConnectOutcome: Sendable {
        case connected(ms: Double)
        case timeout
        case failed(errno: Int32)
    }

    private static let nextSequence = Mutex<UInt16>(0)

    private static func sequence() -> UInt16 {
        nextSequence.withLock { $0 &+= 1; return $0 }
    }

    /// One echo request to `ip`. With `ttl` (the hop limit on IPv6), a router on the way may answer
    /// with time exceeded.
    static func echo(to ip: String, ttl: Int32? = nil, timeout: Duration) -> EchoOutcome {
        guard let dst = Address(ip, port: 0) else { return .sendFailed(errno: EINVAL) }
        let fd = dst.v6 ? socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6) : socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return .sendFailed(errno: errno) }
        defer { close(fd) }
        if var t = ttl {
            if dst.v6 {
                setsockopt(fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &t, socklen_t(MemoryLayout<Int32>.size))
            } else {
                setsockopt(fd, IPPROTO_IP, IP_TTL, &t, socklen_t(MemoryLayout<Int32>.size))
            }
        }

        let seq = sequence()
        // A fresh identifier per echo: if the kernel hands each reply to one socket by identifier,
        // a shared one (the pid) lets a concurrent sweep socket swallow another Probe's reply.
        // Device tests showed ICMPv6 Probes losing about 11% only while sweeps ran.
        let id = UInt16.random(in: 1 ... .max)
        let payload = Array("blinkengraphs".utf8)
        let packet = dst.v6
            ? ICMP6.echoRequest(identifier: id, sequence: seq, payload: payload)
            : ICMP.echoRequest(identifier: id, sequence: seq, payload: payload)
        let start = ContinuousClock.now
        guard send(fd, packet, to: dst) else { return .sendFailed(errno: errno) }

        // Every datagram ICMP socket may see every reply, so match on our sequence.
        while let (bytes, from) = receive(fd, until: start + timeout) {
            // Darwin's datagram ICMP sockets deliver the IPv4 header; ICMPv6 ones deliver none.
            let reply = dst.v6 ? ICMP6.parse(bytes) : ICMP.parse(bytes, includesIPHeader: true)
            guard let reply, reply.sequence == seq else { continue }
            if reply.kind == .echoReply && Address(from, port: 0) != dst { continue }
            return .reply(from: from, kind: reply.kind, ms: (ContinuousClock.now - start).milliseconds)
        }
        return .timeout
    }

    /// One A query for `name` straight to `server`, so the OS resolver cache doesn't hide its latency.
    static func dnsQuery(_ name: String, server: String, timeout: Duration) -> DNSOutcome {
        guard let dst = Address(server, port: 53) else { return .sendFailed(errno: EINVAL) }
        let fd = socket(dst.v6 ? AF_INET6 : AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return .sendFailed(errno: errno) }
        defer { close(fd) }
        let id = UInt16.random(in: .min ... .max)
        let start = ContinuousClock.now
        guard send(fd, DNS.query(id: id, name: name), to: dst) else { return .sendFailed(errno: errno) }
        while let (bytes, from) = receive(fd, until: start + timeout) {
            if Address(from, port: 53) == dst, DNS.parseResponse(bytes, id: id) != nil {
                return .answer(ms: (ContinuousClock.now - start).milliseconds)
            }
        }
        return .timeout
    }

    /// TCP handshake time to `ip:port`: non-blocking connect, then wait for writability.
    /// An NWConnection to an IPv4 literal never became ready on IPv6-only cellular.
    static func tcpConnect(to ip: String, port: UInt16, timeout: Duration) -> ConnectOutcome {
        guard var dst = Address(ip, port: port) else { return .failed(errno: EINVAL) }
        let fd = socket(dst.v6 ? AF_INET6 : AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return .failed(errno: errno) }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let start = ContinuousClock.now
        let r = dst.withSockaddr { connect(fd, $0, $1) }
        if r == 0 { return .connected(ms: (ContinuousClock.now - start).milliseconds) }
        guard errno == EINPROGRESS else { return .failed(errno: errno) }

        while true {
            let remaining = (start + timeout) - ContinuousClock.now
            guard remaining > .zero else { return .timeout }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&pfd, 1, Int32(max(1, remaining.milliseconds.rounded(.up))))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { return .timeout }
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
            return err == 0 ? .connected(ms: (ContinuousClock.now - start).milliseconds) : .failed(errno: err)
        }
    }

    /// The TXT strings answering `name` from `server`, or nil on timeout or a failed send.
    static func dnsTXT(_ name: String, server: String, timeout: Duration) -> [String]? {
        guard let dst = Address(server, port: 53) else { return nil }
        let fd = socket(dst.v6 ? AF_INET6 : AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let id = UInt16.random(in: .min ... .max)
        let start = ContinuousClock.now
        guard send(fd, DNS.query(id: id, name: name, type: DNS.txt), to: dst) else { return nil }
        while let (bytes, from) = receive(fd, until: start + timeout) {
            if Address(from, port: 53) == dst, let strings = DNS.txtRecords(bytes, id: id) { return strings }
        }
        return nil
    }

    /// `host`'s first address of one IP version, from the system resolver. Blocks.
    static func resolve(_ host: String, v6: Bool) -> String? {
        var hints = addrinfo()
        hints.ai_family = v6 ? AF_INET6 : AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return nil }
        defer { freeaddrinfo(list) }
        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dst in
            dst.copyMemory(from: UnsafeRawBufferPointer(start: first.pointee.ai_addr, count: Int(first.pointee.ai_addrlen)))
        }
        return Address.name(of: storage)
    }

    /// `host`'s address, IPv6 first when `preferV6`, else IPv4 first. Blocks on the system resolver.
    static func resolve(_ host: String, preferV6: Bool) -> String? {
        let v6 = resolve(host, v6: true), v4 = resolve(host, v6: false)
        return preferV6 ? (v6 ?? v4) : (v4 ?? v6)
    }

    /// The PTR name for `ip`, or nil when it has none. Blocks on the system resolver.
    static func reverseDNS(_ ip: String) -> String? {
        guard var a = Address(ip, port: 0) else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = a.withSockaddr { getnameinfo($0, $1, &host, socklen_t(host.count), nil, 0, NI_NAMEREQD) }
        return rc == 0 ? String(cString: host) : nil
    }

    private static func send(_ fd: Int32, _ bytes: [UInt8], to dst: Address) -> Bool {
        var dst = dst
        return dst.withSockaddr { sendto(fd, bytes, bytes.count, 0, $0, $1) } == bytes.count
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
            var from = sockaddr_storage()
            var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
            }
            guard n > 0 else { continue }
            return (Array(buf.prefix(n)), Address.name(of: from))
        }
    }
}

/// An IPv4 or IPv6 socket address for an IP literal.
struct Address: Equatable {
    let v6: Bool
    private var storage = sockaddr_storage()

    init?(_ ip: String, port: UInt16) {
        if ip.contains(":") {
            var a = sockaddr_in6()
            a.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            a.sin6_family = sa_family_t(AF_INET6)
            a.sin6_port = port.bigEndian
            guard inet_pton(AF_INET6, ip, &a.sin6_addr) == 1 else { return nil }
            v6 = true
            withUnsafeMutableBytes(of: &storage) { $0.copyBytes(from: withUnsafeBytes(of: a) { Array($0) }) }
        } else {
            var a = sockaddr_in()
            a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            a.sin_family = sa_family_t(AF_INET)
            a.sin_port = port.bigEndian
            guard inet_pton(AF_INET, ip, &a.sin_addr) == 1 else { return nil }
            v6 = false
            withUnsafeMutableBytes(of: &storage) { $0.copyBytes(from: withUnsafeBytes(of: a) { Array($0) }) }
        }
    }

    private var length: socklen_t {
        socklen_t(v6 ? MemoryLayout<sockaddr_in6>.size : MemoryLayout<sockaddr_in>.size)
    }

    mutating func withSockaddr<R>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R {
        let len = length
        return withUnsafePointer(to: &storage) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, len) } }
    }

    /// The address's text form, IPv4 or IPv6.
    static func name(of s: sockaddr_storage) -> String {
        var s = s
        let v6 = Int32(s.ss_family) == AF_INET6
        var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        withUnsafePointer(to: &s) { p in
            if v6 {
                p.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { a in
                    var addr = a.pointee.sin6_addr
                    _ = inet_ntop(AF_INET6, &addr, &text, socklen_t(text.count))
                }
            } else {
                p.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { a in
                    var addr = a.pointee.sin_addr
                    _ = inet_ntop(AF_INET, &addr, &text, socklen_t(text.count))
                }
            }
        }
        return String(cString: text)
    }

    /// Same IP, ignoring port and the rest of the struct.
    static func == (a: Address, b: Address) -> Bool {
        name(of: a.storage) == name(of: b.storage)
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
