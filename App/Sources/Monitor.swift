import BlinkengraphsCore
import Foundation
import Observation

/// Runs the Probe Group while the app is open and keeps the Verdict and Hop Traces current.
@MainActor @Observable
final class Monitor {
    private(set) var stats: [Probe: ProbeStats] = [:]
    private(set) var denied: Set<Probe> = []
    private(set) var verdict: [Finding] = Verdict.evaluate(VerdictInput(probes: []))
    private(set) var path = PathState()
    private(set) var hops: [String: [HopRow]] = [:]
    /// Hop names by address, from reverse DNS (spec rules/hop-trace.md, "Names").
    private(set) var hopNames: [String: String] = [:]
    private var namesRequested: Set<String> = []
    private(set) var results: [Probe: [ProbeResult]] = [:]
    private(set) var now = Date().timeIntervalSince1970

    var dashboard: Dashboard {
        Dashboard(findings: verdict, stats: stats, denied: denied, path: path, hops: hops,
                  hopNames: hopNames, results: results, now: now, history: history)
    }

    /// Minutes older than the RAM History, for the 1h, 24h and 7d graphs.
    let history: RollupHistory
    private let files: RollupFiles
    private var loaded = false

    private let defaults: Defaults
    private let runners: [any ProbeRunner]
    private var linkHistories: LinkHistories
    private var traces: [Link: [String: HopTrace]] = [:]
    private var sweepPlans: [Link: [String: HopSweepPlan]] = [:]
    private var pathWatcher: PathWatcher?
    private var tasks: [Task<Void, Never>] = []

    init(defaults: Defaults) {
        self.defaults = defaults
        linkHistories = LinkHistories(ramSeconds: Double(defaults.history.ramMinutes * 60))
        history = RollupHistory(keepDays: defaults.history.rollupDays)
        files = RollupFiles(keepDays: defaults.history.rollupDays)
        runners = [ICMPProbeRunner(), TCPProbeRunner(), DNSProbeRunner(queryName: defaults.dnsQueryName)]
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

        let group = defaults.probeGroup
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.probeOnce()
                try? await Task.sleep(for: .milliseconds(group.latencyMs))
            }
        })
        for target in group.targets where target.trace {
            tasks.append(Task { [weak self] in
                while !Task.isCancelled {
                    await self?.sweepOnce(target.target)
                    try? await Task.sleep(for: .milliseconds(group.traceMs))
                }
            })
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        pathWatcher?.stop()
        pathWatcher = nil
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
        case Probe.systemDNS: return nil
        default:
            let v6 = Probe(target: target, protocol: "").isIPv6 == true
            return (v6 ? path.ipv6 : path.ipv4 || path.ipv6) ? target : nil
        }
    }

    private func probeOnce() async {
        // spec rules/probe-stats.md: no network path, no Probes; the Verdict says Offline.
        guard path.satisfied else { return refreshVerdict() }
        // Results belong to the Link they were sent on, even if the path changes mid-flight.
        let link = path.link
        let timeout = timeout(intervalMs: defaults.probeGroup.latencyMs)
        let jobs = defaults.probeGroup.probes.compactMap { probe in
            address(of: probe.target).flatMap { addr in
                runners.first { $0.handles(probe) }.map { (probe, addr, $0) }
            }
        }
        await withTaskGroup(of: (Probe, ProbeOutcome).self) { group in
            for (probe, addr, runner) in jobs {
                group.addTask { (probe, await runner.run(probe, address: addr, timeout: timeout)) }
            }
            for await (probe, outcome) in group { record(probe, outcome, on: link) }
        }
        refreshVerdict()
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

    private func refreshVerdict() {
        stats = linkHistories.stats(on: path.link, windowSeconds: Double(defaults.history.recentWindowS))
        results = linkHistories.results(on: path.link)
        now = Date().timeIntervalSince1970
        verdict = Verdict.evaluate(VerdictInput(probes: stats.map { .init(probe: $0.key, stat: $0.value) },
                                                pathUp: path.satisfied, viaVPN: path.vpn))
    }

    private func apply(_ state: PathState) {
        let changed = state.link != path.link
        path = state
        if changed { linkChanged() }
    }

    private func linkChanged() {
        if !denied.isEmpty { denied = [] }
        hops = (traces[path.link] ?? [:]).mapValues(\.table)
        refreshVerdict()
    }

    private func record(_ probe: Probe, _ outcome: ProbeOutcome, on link: Link) {
        let at = Date().timeIntervalSince1970
        let rtt: Double?
        switch outcome {
        case .reply(let ms): rtt = ms
        case .lost: rtt = nil
        case .denied:
            // rules/probe-stats.md: not a loss and not recorded; shown outside the Verdict.
            // Observed state: writing it re-renders the screen, so only write on a change.
            if link == path.link, !denied.contains(probe) { denied.insert(probe) }
            return
        case .unreachable:
            return
        }
        if link == path.link, denied.contains(probe) { denied.remove(probe) }
        let result = ProbeResult(at: at, rttMs: rtt)
        linkHistories.record(probe, result, on: link)
        let closed = history.rollups.record(probe, result, on: link)
        if !closed.isEmpty { Task { [files] in await files.append(closed) } }
    }

    private func sweepOnce(_ target: String) async {
        guard path.satisfied, let addr = address(of: target) else { return }
        // spec rules/hop-trace.md: only over an IP version the path carries natively; through
        // 464XLAT the routers before the translator can't answer.
        let v6 = Probe(target: target, protocol: "").isIPv6 == true
        guard v6 ? path.ipv6 : path.ipv4 else { return }
        let link = path.link
        let cfg = defaults.hopTrace
        var plan = sweepPlans[link]?[target] ?? HopSweepPlan(maxTtl: cfg.maxTtl, fullSweepEveryS: Double(cfg.fullSweepEveryS))
        var trace = traces[link]?[target] ?? HopTrace(hopWindow: cfg.hopWindow)
        let ttls = plan.ttls(at: Date().timeIntervalSince1970, pathLength: trace.pathLength)
        sweepPlans[link, default: [:]][target] = plan

        let timeout = timeout(intervalMs: defaults.probeGroup.traceMs)
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
        // Highest TTL first: past the Target every TTL is `reached`, and the lowest reached one,
        // recorded last, prunes the rows above it.
        for r in results.sorted(by: { $0.ttl > $1.ttl }) { trace.record(r) }
        traces[link, default: [:]][target] = trace
        if link == path.link { hops[target] = trace.table }
        lookUpNames(trace.table.compactMap(\.addr))
    }
}
