// Exercises the socket calls the iOS app will use, without root:
// SOCK_DGRAM ICMP echo, the same with a TTL limit (Hop Trace), UDP DNS, TCP connect.
import Darwin
import Foundation

func now() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e6 }

func addr(_ ip: String, port: UInt16 = 0) -> sockaddr_in {
    var a = sockaddr_in()
    a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    a.sin_family = sa_family_t(AF_INET)
    a.sin_port = port.bigEndian
    inet_pton(AF_INET, ip, &a.sin_addr)
    return a
}

func setTimeout(_ fd: Int32, ms: Int) {
    var tv = timeval(tv_sec: ms / 1000, tv_usec: Int32((ms % 1000) * 1000))
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
}

func checksum(_ b: [UInt8]) -> UInt16 {
    var sum: UInt32 = 0
    var i = 0
    while i + 1 < b.count { sum += UInt32(b[i]) << 8 | UInt32(b[i + 1]); i += 2 }
    if i < b.count { sum += UInt32(b[i]) << 8 }
    while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
    return ~UInt16(sum)
}

func sendTo(_ fd: Int32, _ bytes: [UInt8], _ dst: sockaddr_in) -> Int {
    var d = dst
    return withUnsafePointer(to: &d) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
}

func recvFrom(_ fd: Int32) -> (Int, [UInt8], String) {
    var buf = [UInt8](repeating: 0, count: 1500)
    var from = sockaddr_in()
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let n = withUnsafeMutablePointer(to: &from) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
    }
    var s = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    inet_ntop(AF_INET, &from.sin_addr, &s, socklen_t(INET_ADDRSTRLEN))
    return (n, Array(buf.prefix(max(n, 0))), String(cString: s))
}

func icmp(_ ip: String, ttl: Int32? = nil, seq: UInt16) -> String {
    let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
    guard fd >= 0 else { return "socket failed: \(String(cString: strerror(errno)))" }
    defer { close(fd) }
    setTimeout(fd, ms: 1000)
    if var t = ttl { setsockopt(fd, IPPROTO_IP, IP_TTL, &t, socklen_t(MemoryLayout<Int32>.size)) }
    var pkt: [UInt8] = [8, 0, 0, 0, 0x12, 0x34, UInt8(seq >> 8), UInt8(seq & 0xff)] + Array("blinkengraphs".utf8)
    let c = checksum(pkt); pkt[2] = UInt8(c >> 8); pkt[3] = UInt8(c & 0xff)
    let t0 = now()
    guard sendTo(fd, pkt, addr(ip)) > 0 else { return "send failed: \(String(cString: strerror(errno)))" }
    let (n, bytes, from) = recvFrom(fd)
    guard n > 0 else { return "no reply (\(String(cString: strerror(errno))))" }
    // Darwin DGRAM ICMP sockets deliver the IP header too.
    let ihl = Int(bytes[0] & 0x0f) * 4
    let type = bytes.count > ihl ? bytes[ihl] : 255
    return String(format: "from %@ icmp type %d in %.1f ms (%d bytes)", from, type, now() - t0, n)
}

func dns(_ ip: String) -> String {
    let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    defer { close(fd) }
    setTimeout(fd, ms: 1000)
    var q: [UInt8] = [0xbe, 0xef, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]
    for label in "cloudflare.com".split(separator: ".") { q.append(UInt8(label.utf8.count)); q += label.utf8 }
    q += [0, 0, 1, 0, 1]
    let t0 = now()
    guard sendTo(fd, q, addr(ip, port: 53)) > 0 else { return "send failed" }
    let (n, b, _) = recvFrom(fd)
    guard n > 3 else { return "no reply" }
    return String(format: "rcode %d, %d answers in %.1f ms", b[3] & 0x0f, Int(b[6]) << 8 | Int(b[7]), now() - t0)
}

func tcp(_ ip: String, _ port: UInt16) -> String {
    let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    defer { close(fd) }
    var tv = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var a = addr(ip, port: port)
    let t0 = now()
    let r = withUnsafePointer(to: &a) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    return r == 0 ? String(format: "connected in %.1f ms", now() - t0) : "failed: \(String(cString: strerror(errno)))"
}

print("uid \(getuid())")
for (i, t) in ["1.1.1.1", "8.8.8.8"].enumerated() { print("icmp \(t): \(icmp(t, seq: UInt16(i)))") }
for ttl: Int32 in 1...6 { print("icmp 1.1.1.1 ttl \(ttl): \(icmp("1.1.1.1", ttl: ttl, seq: UInt16(100 + ttl)))") }
for t in ["1.1.1.1", "8.8.8.8"] { print("dns \(t): \(dns(t))") }
for t in ["1.1.1.1", "8.8.8.8"] { print("tcp \(t):443: \(tcp(t, 443))") }
