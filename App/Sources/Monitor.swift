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

    private let defaults: Defaults
    private let runners: [any ProbeRunner]
    private var histories: [Probe: ProbeHistory] = [:]
    private var traces: [String: HopTrace] = [:]
    private var sweepPlans: [String: HopSweepPlan] = [:]
    private var pathWatcher: PathWatcher?
    private var tasks: [Task<Void, Never>] = []

    init(defaults: Defaults) {
        self.defaults = defaults
        runners = [ICMPProbeRunner(), TCPProbeRunner(), DNSProbeRunner(queryName: defaults.dnsQueryName)]
    }

    func start() {
        guard tasks.isEmpty else { return }
        let watcher = PathWatcher()
        watcher.start { [weak self] state in Task { @MainActor in self?.path = state } }
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

    /// The Target's IPv4 address, or nil when it can't be probed right now.
    private func address(of target: String) -> String? {
        switch target {
        case Probe.gateway: path.gateway
        case Probe.systemDNS: nil
        default: target
        }
    }

    private func probeOnce() async {
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
            for await (probe, outcome) in group { record(probe, outcome) }
        }
        let window = Double(defaults.history.recentWindowS)
        stats = histories.mapValues { $0.stats(windowSeconds: window) }
        verdict = Verdict.evaluate(VerdictInput(probes: stats.map { .init(probe: $0.key, stat: $0.value) }))
    }

    private func record(_ probe: Probe, _ outcome: ProbeOutcome) {
        let at = Date().timeIntervalSince1970
        let rtt: Double?
        switch outcome {
        case .reply(let ms): rtt = ms
        case .lost: rtt = nil
        case .denied:
            // rules/probe-stats.md: not a loss and not recorded; shown outside the Verdict.
            denied.insert(probe)
            return
        }
        denied.remove(probe)
        histories[probe, default: ProbeHistory(ramSeconds: Double(defaults.history.ramMinutes * 60))]
            .record(ProbeResult(at: at, rttMs: rtt))
    }

    private func sweepOnce(_ target: String) async {
        guard let addr = address(of: target) else { return }
        let cfg = defaults.hopTrace
        var plan = sweepPlans[target] ?? HopSweepPlan(maxTtl: cfg.maxTtl, fullSweepEveryS: Double(cfg.fullSweepEveryS))
        var trace = traces[target] ?? HopTrace(hopWindow: cfg.hopWindow)
        let ttls = plan.ttls(at: Date().timeIntervalSince1970, pathLength: trace.pathLength)
        sweepPlans[target] = plan

        let timeout = timeout(intervalMs: defaults.probeGroup.traceMs)
        let results = await withTaskGroup(of: HopResult.self) { group in
            for ttl in ttls {
                group.addTask {
                    switch await offPool({ Sockets.echo(to: addr, ttl: Int32(ttl), timeout: timeout) }) {
                    case .reply(let from, let kind, let ms):
                        HopResult(ttl: ttl, addr: from, rttMs: ms, reached: kind == .echoReply)
                    case .timeout, .sendFailed:
                        HopResult(ttl: ttl, addr: nil, rttMs: nil, reached: false)
                    }
                }
            }
            var results: [HopResult] = []
            for await r in group { results.append(r) }
            return results
        }
        // Highest TTL first: past the Target every TTL is `reached`, and the lowest reached one,
        // recorded last, prunes the rows above it.
        for r in results.sorted(by: { $0.ttl > $1.ttl }) { trace.record(r) }
        traces[target] = trace
        hops[target] = trace.table
    }
}
