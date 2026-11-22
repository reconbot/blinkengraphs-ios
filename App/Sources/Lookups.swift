import BlinkengraphsCore
import dnssd
import Foundation
import Network

// MARK: - System DNS

/// The `system-dns` Probe: a lookup through the OS resolver. iOS has no public API for the
/// resolver's address, so unlike the other DNS Probes this can't query it directly. Each lookup
/// asks for a fresh random name under `domain`, so no cache answers and the resolver must reply
/// itself; NXDOMAIN is a reply. ADR 0008.
struct SystemDNSProbeRunner: ProbeRunner {
    let domain: String

    func handles(_ probe: Probe) -> Bool { probe.target == Probe.systemDNS && probe.protocol == "dns" }

    func run(_ probe: Probe, address: String, timeout: Duration) async -> ProbeOutcome {
        let label = String((0..<12).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        return await SystemResolver.lookup("\(label).\(domain)", timeout: timeout)
    }
}

private enum SystemResolver {
    static let queue = DispatchQueue(label: "blinkengraphs.system-dns")

    /// One DNSServiceGetAddrInfo; every callback, the timeout and the teardown run on `queue`.
    final class Lookup: @unchecked Sendable {
        var ref: DNSServiceRef?
        var continuation: CheckedContinuation<ProbeOutcome, Never>?
        let start = ContinuousClock.now

        func finish(_ outcome: ProbeOutcome) {
            guard let continuation else { return }
            self.continuation = nil
            if let ref { DNSServiceRefDeallocate(ref) }
            ref = nil
            continuation.resume(returning: outcome)
            Unmanaged.passUnretained(self).release()
        }
    }

    static func lookup(_ name: String, timeout: Duration) async -> ProbeOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                let lookup = Lookup()
                lookup.continuation = continuation
                let context = Unmanaged.passRetained(lookup).toOpaque()
                // ReturnIntermediates: without it an NXDOMAIN gets no callback at all.
                let error = DNSServiceGetAddrInfo(&lookup.ref, DNSServiceFlags(kDNSServiceFlagsReturnIntermediates),
                                                  0, 0, name, { _, _, _, error, _, _, _, context in
                    let lookup = Unmanaged<Lookup>.fromOpaque(context!).takeUnretainedValue()
                    let answered = [kDNSServiceErr_NoError, kDNSServiceErr_NoSuchRecord, kDNSServiceErr_NoSuchName]
                        .contains(Int(error))
                    lookup.finish(answered ? .reply(ms: (ContinuousClock.now - lookup.start).milliseconds) : .lost)
                }, context)
                guard Int(error) == kDNSServiceErr_NoError, let ref = lookup.ref else {
                    lookup.ref = nil
                    return lookup.finish(.lost)
                }
                DNSServiceSetDispatchQueue(ref, queue)
                queue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout.milliseconds))) { lookup.finish(.lost) }
            }
        }
    }
}

// MARK: - Captive Portal

/// spec rules/verdict.md, "Captive Portal": a plain-HTTP GET that a portal intercepts. True when
/// the answer is anything but an empty 204; nil when nothing answered, which isn't a portal.
enum CaptivePortalCheck {
    static func run(_ url: String) async -> Bool? {
        guard let url = URL(string: url) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse else { return nil }
        return !(http.statusCode == 204 && data.isEmpty)
    }
}

// MARK: - Public Address

/// spec rules/public-address.md: per IP version, a TXT whoami sent straight to Cloudflare's
/// nameserver and an HTTPS checkip, read together.
enum PublicAddressLookup {
    static func run(_ family: IPFamily, _ config: Defaults.PublicAddressDefaults) async -> PublicAddressReading {
        async let txt = offPool { () -> [String]? in
            guard let server = Sockets.resolve(config.dnsServer, v6: family == .ipv6) else { return nil }
            return Sockets.dnsTXT(config.dnsName, server: server, timeout: .seconds(3))
        }
        async let body = https(config.httpsURL, family: family)
        return PublicAddress.read(family: family, dnsTXT: await txt, httpsBody: await body)
    }

    /// One HTTP/1.1 GET over TLS, held to one IP version, which URLSession can't do.
    static func https(_ urlString: String, family: IPFamily) async -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        let params = NWParameters.tls
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = family == .ipv6 ? .v6 : .v4
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 443, using: params)
        let path = url.path.isEmpty ? "/" : url.path
        let request = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: blinkengraphs\r\nConnection: close\r\n\r\n"
        let response = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let once = Once(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
                    receiveAll(connection, into: Data()) { once.resume($0) }
                case .failed, .waiting, .cancelled:
                    once.resume(nil)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { once.resume(nil) }
        }
        connection.cancel()
        guard let response, let text = String(data: response, encoding: .utf8),
              let split = text.range(of: "\r\n\r\n"), text.hasPrefix("HTTP/1.1 200") || text.hasPrefix("HTTP/1.0 200")
        else { return nil }
        let headers = text[..<split.lowerBound].lowercased()
        let body = String(text[split.upperBound...])
        // checkip's answer fits one chunk: its size line, then the address.
        if headers.contains("transfer-encoding: chunked") {
            let lines = body.components(separatedBy: "\r\n")
            return lines.count > 1 ? lines[1] : nil
        }
        return body
    }

    private static func receiveAll(_ c: NWConnection, into data: Data, done: @escaping @Sendable (Data?) -> Void) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { chunk, _, complete, error in
            let data = data + (chunk ?? Data())
            if complete || error != nil || data.count > 65_536 { done(data.isEmpty ? nil : data) }
            else { receiveAll(c, into: data, done: done) }
        }
    }

    /// Resumes a continuation at most once, from whichever callback gets there first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data?, Never>?
        init(_ c: CheckedContinuation<Data?, Never>) { continuation = c }
        func resume(_ value: Data?) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }
}
