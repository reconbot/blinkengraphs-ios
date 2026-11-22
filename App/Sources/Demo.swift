import BlinkengraphsCore
import Foundation

/// Fixed, seeded states for screenshots and previews: launch with `-demo <name>`.
/// The Verdict and stats come from the real rules, fed with generated results.
enum Demo: String, CaseIterable {
    case wifi, ispLoss = "isp-loss", cellular, vpn, offline, captive

    static var fromLaunchArguments: Demo? {
        UserDefaults.standard.string(forKey: "demo").flatMap(Demo.init(rawValue:))
    }

    /// `-range` at launch; nil (as in previews) means any range may be shown.
    private static var launchRange: GraphRange? {
        UserDefaults.standard.string(forKey: "range").flatMap(GraphRange.init(rawValue:))
    }

    /// `-ready <token>`: once the first screen has drawn, write an empty file named `token` to
    /// Documents, so the screenshot script waits exactly as long as needed instead of a fixed sleep.
    @MainActor
    static func signalReady() async {
        guard let token = UserDefaults.standard.string(forKey: "ready"),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        // Two frames: the first lays out, the second has drawn.
        try? await Task.sleep(for: .milliseconds(100))
        FileManager.default.createFile(atPath: docs.appendingPathComponent(token).path, contents: nil)
    }

    @MainActor
    func dashboard(defaults: Defaults = SpecResources.defaults, now: Double = 1_800_000_000) -> Dashboard {
        var rng = SplitMix64(seed: UInt64(rawValue.hashValueStable))
        var d = Dashboard(path: path, now: now)
        // Raw for the range shown; the screenshot of 1h needs an hour, the others 15 minutes.
        let rawSpan = Self.launchRange == .oneHour ? 3600.0 : 900
        let start = now - rawSpan
        let end = self == .offline ? now - 95 : now
        // The same Measurements the app runs, fed generated results, so a screenshot shows what the
        // rules would really show.
        let link = d.path.link
        // A week of A1 Rows before Raw begins takes a while in a Debug build: only for a range that shows them.
        let seeded = (Self.launchRange?.span ?? .max) > Int(rawSpan)
            ? archives(defaults: defaults, start: start, link: link, rng: &rng) : nil
        var m = Measurements(defaults: defaults, settle: 0, history: seeded)
        m.setPath(link: link, up: true, viaVPN: d.path.vpn)
        m.resume(at: start)
        // With cellular measured too, Wi-Fi scenarios show two networks side by side.
        let cell = Link(interface: "pdp_ip0", gateway: nil)
        let withCellular = self == .wifi || self == .ispLoss
        m.setActiveLinks(withCellular ? [link, cell] : [link])
        var t = start + 0.2
        while t <= end {
            let outcomes: [(Probe, Measurements.Outcome)] = defaults.probeGroup.probes.compactMap { probe in
                guard let shape = shape(probe) else { return nil }
                let spike = shape.spikeEvery > 0 && Int(t) % shape.spikeEvery < 20
                // Only the ISP scenario loses Probes in its spikes; elsewhere a spike is latency alone.
                let lost = rng.unit() < shape.loss + (spike && self == .ispLoss ? 0.25 : 0)
                let rtt = shape.base + abs(rng.normal()) * shape.jitter + (spike ? shape.base * 0.8 : 0)
                return (probe, lost ? .lost : .reply(ms: rtt))
            }
            m.commit(.init(start: t, end: t + 0.3, link: link, outcomes: outcomes))
            if withCellular {
                let carrier: [(Probe, Measurements.Outcome)] = defaults.probeGroup.probes.compactMap { probe in
                    guard let shape = Demo.cellular.shape(probe) else { return nil }
                    return (probe, .reply(ms: shape.base + abs(rng.normal()) * shape.jitter))
                }
                m.commit(.init(start: t, end: t + 0.3, link: cell, outcomes: carrier))
            }
            t += 1
        }
        m.setCaptivePortal(self == .captive, checkedOn: link)
        m.setPath(link: link, up: d.path.satisfied, viaVPN: d.path.vpn)
        m.advance(now: now)
        let snapshot = m.snapshot(now: now)
        d.findings = snapshot.findings
        d.stats = snapshot.stats
        d.window = snapshot.window
        d.links = snapshot.links
        d.history = m.history
        d.captivePortal = snapshot.captivePortal
        // Documentation addresses (RFC 5737, RFC 3849), never a real one.
        d.publicAddress = switch self {
        case .offline, .captive: [:]
        case .cellular: [.ipv4: PublicAddressReading(state: .nat64, address: "192.0.2.44"),
                         .ipv6: PublicAddressReading(state: .agree, address: "2001:db8:5a::17", asn: "64496")]
        case .vpn: [.ipv4: PublicAddressReading(state: .differ, dns: "198.51.100.23", https: "203.0.113.7", asn: "64497"),
                    .ipv6: PublicAddressReading(state: .none)]
        default: [.ipv4: PublicAddressReading(state: .agree, address: "203.0.113.7", asn: "64500"),
                  .ipv6: PublicAddressReading(state: .agree, address: "2001:db8:1:4000::1", asn: "64500")]
        }
        if self != .offline && self != .captive { (d.hops, d.hopNames) = hops }
        return d
    }

    /// Eight days of A1 Rows before Raw begins, from which the app's own writer builds A2 and A3.
    /// The phone was in use by day and the app closed overnight, so nights are Pauses. In the ISP
    /// scenario the trouble starts two hours ago.
    private func archives(defaults: Defaults, start: Double, link: Link, rng: inout SplitMix64) -> History {
        var h = History(defaults: defaults)
        let step = 300, last = Int(start) / step * step - step, first = last - 8 * 86_400
        for probe in defaults.probeGroup.probes {
            for m in stride(from: first, through: last, by: step) {
                let hour = (m / 3600) % 24
                if (1...6).contains(hour) && last - m > 7200 { continue }
                let troubled = self == .ispLoss && last - m <= 7200
                guard let shape = (troubled || self != .ispLoss ? self : .wifi).shape(probe) else { continue }
                var row = Row()
                for _ in 0..<20 {
                    let lost = rng.unit() < shape.loss
                    row.record(lost ? nil : (shape.base + abs(rng.normal()) * shape.jitter * 0.6).rounded())
                }
                h.insert(row, key: HistoryKey(link: link, probe: probe), level: 0, m: m)
            }
        }
        // The same nights the Rows skip: 01:00–07:00, ending where the last two hours begin.
        for day in stride(from: first / 86_400 * 86_400, through: last, by: 86_400) {
            let end = min(day + 7 * 3600, last - 7200)
            if end > day + 3600 { h.add(Pause(begin: Double(day + 3600), end: Double(end))) }
        }
        return h
    }

    fileprivate struct Shape { var base: Double; var jitter: Double; var loss: Double; var spikeEvery = 0 }

    fileprivate func shape(_ p: Probe) -> Shape? {
        let v6 = p.isIPv6 == true
        let gw = p.target == Probe.gateway
        let factor = p.protocol.hasPrefix("tcp") ? 1.15 : p.protocol == "dns" ? 1.3 : 1
        switch self {
        case .wifi, .offline:
            if gw { return Shape(base: 2.5, jitter: 1.2, loss: 0) }
            return Shape(base: (v6 ? 11 : 13) * factor, jitter: 2.5, loss: 0, spikeEvery: 240)
        case .ispLoss:
            if gw { return Shape(base: 3, jitter: 1.5, loss: 0) }
            return Shape(base: (v6 ? 78 : 86) * factor, jitter: 16, loss: 0.21, spikeEvery: 150)
        case .cellular:
            if gw { return nil }
            return Shape(base: (v6 ? 31 : 38) * factor, jitter: 9, loss: 0, spikeEvery: 200)
        case .vpn:
            if gw { return Shape(base: 3, jitter: 1.4, loss: 0) }
            return Shape(base: (v6 ? 44 : 47) * factor, jitter: 6, loss: 0, spikeEvery: 300)
        case .captive:
            // The portal answers the Gateway and swallows everything else.
            if gw { return Shape(base: 3.5, jitter: 1.5, loss: 0) }
            return Shape(base: 20, jitter: 2, loss: 1)
        }
    }

    private var path: PathState {
        var p = PathState()
        p.ipv4 = true; p.ipv6 = true; p.dns = true; p.linkQuality = "Good"
        switch self {
        case .wifi, .ispLoss, .captive:
            p.interfaces = ["Wi-Fi"]; p.interfaceName = "en0"; p.gateway = "192.168.1.1"
        case .cellular:
            p.interfaces = ["Cellular"]; p.interfaceName = "pdp_ip0"; p.radio = "5G"
            p.ipv4 = false; p.expensive = true
        case .vpn:
            p.interfaces = ["VPN", "Wi-Fi"]; p.interfaceName = "utun4"; p.gateway = "192.168.1.1"; p.vpn = true
        case .offline:
            p.satisfied = false; p.interfaces = []; p.ipv4 = false; p.ipv6 = false; p.dns = false
            p.linkQuality = nil
        }
        return p
    }

    private var hops: ([String: [HopRow]], [String: String]) {
        func row(_ ttl: Int, _ addr: String?, _ ms: Double, loss: Double = 0) -> HopRow {
            addr == nil
                ? HopRow(ttl: ttl, addr: nil, sent: 60, loss: 1, lastMs: nil, bestMs: nil, avgMs: nil, worstMs: nil)
                : HopRow(ttl: ttl, addr: addr, sent: 60, loss: loss, lastMs: ms * 1.04, bestMs: ms * 0.8,
                         avgMs: ms, worstMs: ms * 1.9)
        }
        let isp = self == .ispLoss ? 0.22 : 0
        let scale = self == .ispLoss ? 6.5 : self == .vpn ? 3.4 : 1
        let v4 = [row(1, "192.168.1.1", 2.4), row(2, "100.64.0.1", 7.9 * scale, loss: isp),
                  row(3, "203.0.113.9", 9.6 * scale, loss: isp), row(4, nil, 0),
                  row(5, "198.51.100.17", 12.1 * scale, loss: isp), row(6, "1.1.1.1", 12.8 * scale, loss: isp)]
        let v6 = [row(1, "2001:db8:1::1", 2.6), row(2, "2001:db8:ff::1", 8.4 * scale, loss: isp),
                  row(3, "2001:db8:ff:10::2", 10.2 * scale, loss: isp),
                  row(4, "2606:4700:4700::1111", 11.3 * scale, loss: isp)]
        let names = ["192.168.1.1": "router.lan", "203.0.113.9": "ae2.cr1.example.net",
                     "198.51.100.17": "cloudflare.ix.example.net", "1.1.1.1": "one.one.one.one",
                     "2001:db8:ff::1": "lo0.bras1.example.net", "2606:4700:4700::1111": "one.one.one.one"]
        switch self {
        case .cellular:
            return (["2606:4700:4700::1111": [row(1, nil, 0), row(2, "2001:db8:ff::1", 24), row(3, nil, 0),
                                              row(4, "2001:db8:ff:10::2", 29), row(5, "2606:4700:4700::1111", 31)]],
                    names)
        default:
            return (["1.1.1.1": v4, "2606:4700:4700::1111": v6], names)
        }
    }
}

/// Deterministic, so every screenshot run draws the same lines.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    /// Box–Muller.
    mutating func normal() -> Double { (-2 * log(max(unit(), 1e-12))).squareRoot() * cos(2 * .pi * unit()) }
}

private extension String {
    /// `hashValue` changes per launch; screenshots need the same seed every run.
    var hashValueStable: Int { utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) } }
}
