import BlinkengraphsCore
import Foundation
import Observation

/// Runs the Probe Group, the Hop Traces and the lookups while the app is open, feeding their
/// results to `Measurements` and publishing one snapshot per refresh. Scheduling and sockets
/// live here; what the results mean lives in the core (ADR 0009).
@MainActor @Observable
final class Monitor {
    /// Observed: each write re-renders the screen, so it changes once per refresh.
    private(set) var snapshot: Measurements.Snapshot
    private(set) var path = PathState()
    /// Hop names by address, from reverse DNS (spec rules/hop-trace.md, "Names").
    private(set) var hopNames: [String: String] = [:]
    private(set) var now = Date().timeIntervalSince1970
    private(set) var layout: TargetLayout

    var dashboard: Dashboard {
        Dashboard(findings: snapshot.findings, stats: snapshot.stats, denied: snapshot.denied, path: path,
                  hops: snapshot.hops, hopNames: hopNames, results: snapshot.results, now: now,
                  history: history, layout: layout, captivePortal: snapshot.captivePortal,
                  publicAddress: snapshot.publicAddress)
    }

    /// Minutes older than the RAM History, for the 1h, 24h and 7d graphs.
    @ObservationIgnored let history: RollupHistory
    @ObservationIgnored private var measurements: Measurements
    @ObservationIgnored private let files: RollupFiles
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var namesRequested: Set<String> = []
    @ObservationIgnored private let defaults: Defaults
    /// The user's Probe Group (Settings → Targets), else the spec's.
    @ObservationIgnored private var group: Defaults.ProbeGroup
    /// Name Targets resolved, and when; looked up again after 30 s (CONTEXT.md "Target").
    @ObservationIgnored private var resolved: [String: (address: String?, at: Double)] = [:]
    @ObservationIgnored private let runners: [any ProbeRunner]
    @ObservationIgnored private var pathWatcher: PathWatcher?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(defaults: Defaults, group: Defaults.ProbeGroup) {
        self.defaults = defaults
        self.group = group
        layout = TargetLayout(group)
        measurements = Measurements(defaults: defaults)
        measurements.setProbeGroup(group)
        snapshot = measurements.snapshot()
        history = RollupHistory(keepDays: defaults.history.rollupDays)
        files = RollupFiles(keepDays: defaults.history.rollupDays)
        runners = [ICMPProbeRunner(), TCPProbeRunner(), DNSProbeRunner(queryName: defaults.dnsQueryName),
                   SystemDNSProbeRunner(domain: defaults.dnsQueryName)]
    }

    func start() {
        guard tasks.isEmpty else { return }
        if !loaded {
            loaded = true
            Task { [files, history] in
                for stored in await files.load() { history.rollups.insert(stored) }
            }
        }
        let watcher = PathWatcher()
        watcher.start { [weak self] state in Task { @MainActor in self?.apply(state) } }
        pathWatcher = watcher

        let group = self.group
        repeating(every: .milliseconds(group.latencyMs)) { await $0.probeOnce() }
        repeating(every: .seconds(60)) { await $0.checkCaptivePortal() }
        repeating(every: .seconds(defaults.publicAddress.refreshS)) { await $0.lookUpPublicAddress() }
        for target in group.targets where target.trace {
            repeating(every: .milliseconds(group.traceMs)) { await $0.sweepOnce(target.target) }
        }
    }

    /// After the user edits the Targets: measure the new group from the next round.
    func setProbeGroup(_ group: Defaults.ProbeGroup) {
        guard group != self.group else { return }
        self.group = group
        layout = TargetLayout(group)
        measurements.setProbeGroup(group)
        if !tasks.isEmpty {
            stop()
            start()
        }
        publish()
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        pathWatcher?.stop()
        pathWatcher = nil
    }

    private func repeating(every interval: Duration, _ work: @escaping @MainActor @Sendable (Monitor) async -> Void) {
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await work(self)
                try? await Task.sleep(for: interval)
            }
        })
    }

    private func publish() {
        snapshot = measurements.snapshot()
        now = Date().timeIntervalSince1970
    }

    private func timeout(intervalMs: Int) -> Duration {
        .milliseconds(defaults.probeTimeoutMs(intervalMs: intervalMs))
    }

    /// The Target's address, or nil when it can't be probed on this path right now.
    /// IPv6 Targets need IPv6 on the path. IPv4 ones need IPv4, or IPv6 that iOS may translate
    /// (464XLAT); a send that then finds no route reports `unreachable`.
    private func address(of target: String) -> String? {
        switch target {
        case Probe.gateway: return path.gateway
        // The OS resolver needs no address (SystemDNSProbeRunner).
        case Probe.systemDNS: return "system"
        default:
            // A name Target goes to the address it resolved to; unresolved, it's skipped.
            let literal = Probe(target: target, protocol: "").isIPv6 != nil
            guard let address = literal ? target : resolved[target]?.address else { return nil }
            let v6 = address.contains(":")
            return (v6 ? path.ipv6 : path.ipv4 || path.ipv6) ? address : nil
        }
    }

    /// Resolves name Targets that are new or older than 30 s, preferring IPv6 when the path has it.
    private func refreshNames() async {
        let nowS = Date().timeIntervalSince1970, preferV6 = path.ipv6
        let due = group.targets.map(\.target).filter { t in
            t != Probe.gateway && t != Probe.systemDNS && Probe(target: t, protocol: "").isIPv6 == nil
                && nowS - (resolved[t]?.at ?? -.infinity) >= 30
        }
        guard !due.isEmpty else { return }
        await withTaskGroup(of: (String, String?).self) { lookups in
            for name in due {
                lookups.addTask { (name, await offPool { Sockets.resolve(name, preferV6: preferV6) }) }
            }
            for await (name, address) in lookups { resolved[name] = (address, nowS) }
        }
    }

    private func probeOnce() async {
        // spec rules/probe-stats.md: no network path, no Probes; the Verdict says Offline.
        guard path.satisfied else { return publish() }
        await refreshNames()
        // Results belong to the Link they were sent on, even if the path changes mid-flight.
        let link = path.link
        let timeout = timeout(intervalMs: group.latencyMs)
        let jobs = group.probes.compactMap { probe in
            address(of: probe.target).flatMap { addr in
                runners.first { $0.handles(probe) }.map { (probe, addr, $0) }
            }
        }
        var closed: [StoredMinute] = []
        await withTaskGroup(of: (Probe, Measurements.Outcome).self) { group in
            for (probe, addr, runner) in jobs {
                group.addTask { (probe, await runner.run(probe, address: addr, timeout: timeout)) }
            }
            for await (probe, outcome) in group {
                if let result = measurements.record(probe, outcome, sentOn: link, at: Date().timeIntervalSince1970) {
                    closed += history.rollups.record(probe, result, on: link)
                }
            }
        }
        if !closed.isEmpty { Task { [files] in await files.append(closed) } }
        publish()
    }

    private func checkCaptivePortal() async {
        guard path.satisfied else { return }
        let link = path.link
        // No answer at all isn't a portal: keep the last known state.
        guard let portal = await CaptivePortalCheck.run(defaults.captivePortalURL) else { return }
        measurements.setCaptivePortal(portal, checkedOn: link)
        publish()
    }

    private func lookUpPublicAddress() async {
        guard path.satisfied else { return }
        let link = path.link, config = defaults.publicAddress
        async let v4 = PublicAddressLookup.run(.ipv4, config)
        async let v6 = PublicAddressLookup.run(.ipv6, config)
        measurements.setPublicAddress([.ipv4: await v4, .ipv6: await v6], lookedUpOn: link)
        publish()
    }

    /// Once per address, off the main actor; a sweep never waits for it.
    private func lookUpNames(_ addrs: [String]) {
        guard defaults.hopTrace.reverseDns else { return }
        for addr in addrs where namesRequested.insert(addr).inserted {
            Task { [weak self] in
                guard let name = await offPool({ Sockets.reverseDNS(addr) }) else { return }
                self?.hopNames[addr] = name
            }
        }
    }

    private func apply(_ state: PathState) {
        path = state
        if measurements.setPath(link: state.link, up: state.satisfied, viaVPN: state.vpn) {
            Task { [weak self] in
                await self?.checkCaptivePortal()
                await self?.lookUpPublicAddress()
            }
        }
        publish()
    }

    private func sweepOnce(_ target: String) async {
        guard path.satisfied, let addr = address(of: target) else { return }
        // spec rules/hop-trace.md: only over an IP version the path carries natively; through
        // 464XLAT the routers before the translator can't answer.
        let v6 = addr.contains(":")
        guard v6 ? path.ipv6 : path.ipv4 else { return }
        let link = path.link
        let ttls = measurements.sweepTTLs(target, at: Date().timeIntervalSince1970)
        let timeout = timeout(intervalMs: group.traceMs)
        // A sweep whose sends find no route records nothing: the path can't reach this IP version.
        let results = await withTaskGroup(of: HopResult?.self) { group in
            for ttl in ttls {
                group.addTask {
                    switch await offPool({ Sockets.echo(to: addr, ttl: Int32(ttl), timeout: timeout) }) {
                    case .reply(let from, let kind, let ms):
                        HopResult(ttl: ttl, addr: from, rttMs: ms, reached: kind == .echoReply)
                    case .sendFailed(let e) where noRoute(e):
                        nil
                    case .timeout, .sendFailed:
                        HopResult(ttl: ttl, addr: nil, rttMs: nil, reached: false)
                    }
                }
            }
            var results: [HopResult] = []
            for await r in group { if let r { results.append(r) } }
            return results
        }
        measurements.recordSweep(results, target: target, sentOn: link)
        lookUpNames(results.compactMap(\.addr))
    }
}
