import BlinkengraphsCore
import Foundation
import Observation
import UIKit

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
                  hops: snapshot.hops, hopNames: hopNames, window: snapshot.window, now: now,
                  history: measurements.history, layout: layout, live: true, captivePortal: snapshot.captivePortal,
                  publicAddress: snapshot.publicAddress)
    }

    @ObservationIgnored private var measurements: Measurements
    @ObservationIgnored private let store = HistoryStore()
    @ObservationIgnored private var loaded = false
    /// How often History reaches disk while measuring; the spec allows at most 10 s (ADR 0016).
    static let saveEvery: Duration = .seconds(5)
    @ObservationIgnored private var namesRequested: Set<String> = []
    @ObservationIgnored private let defaults: Defaults
    /// The user's Probe Group (Settings → Targets), else the spec's.
    @ObservationIgnored private var group: Defaults.ProbeGroup
    /// Name Targets resolved, and when; looked up again after 30 s (CONTEXT.md "Target").
    @ObservationIgnored private var resolved: [String: (address: String?, at: Double)] = [:]
    @ObservationIgnored private let runners: [any ProbeRunner]
    @ObservationIgnored private var pathWatcher: PathWatcher?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// Probes wait for the path to settle after a network change (ADR 0013). One second is a
    /// first guess, to tune from what devices show.
    @ObservationIgnored private var settle = PathSettle(quiet: 1)
    /// After the app returns, the Pause lasts this much longer: Probes sent before the network
    /// is usable again aren't counted (spec rules/history.md, "Pauses"). The spec vectors' 2 s,
    /// until a device test sets it (docs/plan-spec-5.md, "Device tests").
    static let resumeSettle = 2.0

    init(defaults: Defaults, group: Defaults.ProbeGroup) {
        self.defaults = defaults
        self.group = group
        layout = TargetLayout(group)
        measurements = Measurements(defaults: defaults, settle: Self.resumeSettle)
        measurements.setProbeGroup(group)
        snapshot = measurements.snapshot(now: Date().timeIntervalSince1970)
        // Spec 5 replaced Rollups; the owner chose to drop them, not convert them (ADR 0015).
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: support.appendingPathComponent("rollups", isDirectory: true))
        runners = [ICMPProbeRunner(), TCPProbeRunner(), DNSProbeRunner(queryName: defaults.dnsQueryName),
                   SystemDNSProbeRunner(domain: defaults.dnsQueryName)]
    }

    func start() {
        guard tasks.isEmpty else { return }
        guard loaded else {
            tasks.append(Task { [weak self] in
                await self?.load()
                guard let self, !Task.isCancelled else { return }
                self.tasks = []
                self.start()
            })
            return
        }
        // Launch, or a return from the background: the Pause ends a settle time from now.
        measurements.resume(at: Date().timeIntervalSince1970)
        // The path may have changed while we were away; wait for the watcher's first report.
        settle.reset()
        let watcher = PathWatcher()
        watcher.start { [weak self] state in Task { @MainActor in self?.apply(state) } }
        pathWatcher = watcher

        let group = self.group
        rounds(every: Double(group.latencyMs) / 1000)
        repeating(every: Self.saveEvery) { await $0.save() }
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
        // A Round still in flight is cut by this Pause and records nothing. The Pause reaches
        // disk now: iOS may end the suspended app without running any more of its code.
        let now = Date().timeIntervalSince1970
        measurements.pause(at: now)
        measurements.mark(at: now)
        let records = measurements.takeUnsaved()
        let store = store
        let task = BackgroundTask(name: "Save history")
        Task {
            await store.append(records, now: Int(now))
            task.end()
        }
        publish()
    }

    /// Restores History from disk once, at launch: a kill leaves a Pause from the newest record
    /// to now. Steps that ended while the app was away are written, then the Archive file is
    /// rewritten to what retention keeps.
    private func load() async {
        guard !loaded else { return }
        let records = await store.load()
        var history = History(defaults: defaults)
        history.replay(records)
        let now = Date().timeIntervalSince1970
        measurements.restore(history, launch: now)
        measurements.advance(now: now)
        _ = measurements.takeUnsaved()
        await store.compact(measurements.history.archiveRecords)
        await store.prune(rawCutoff: measurements.history.rawCutoff(now: Int(now)))
        loaded = true
    }

    /// What changed since the last save reaches disk. While nothing else happens, as when Offline,
    /// a mark records that measuring went on.
    private func save() async {
        let now = Date().timeIntervalSince1970
        var records = measurements.takeUnsaved()
        if !records.contains(where: { if case .result = $0 { true } else { false } }) {
            measurements.mark(at: now)
            records += measurements.takeUnsaved()
        }
        await store.append(records, now: Int(now))
        await store.prune(rawCutoff: measurements.history.rawCutoff(now: Int(now)))
    }

    /// Probe Rounds on the spec's fixed grid (RoundClock), each committed whole with its start.
    private func rounds(every interval: Double) {
        tasks.append(Task { [weak self] in
            var clock = RoundClock(start: Date().timeIntervalSince1970, interval: interval)
            while !Task.isCancelled {
                guard let self else { return }
                await self.probeOnce(start: clock.start)
                clock.finished(at: Date().timeIntervalSince1970)
                let wait = clock.start - Date().timeIntervalSince1970
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            }
        })
    }

    /// On a fixed beat: each round starts `interval` after the last one started, not after it
    /// ended, so samples arrive evenly. A round that overruns starts the next one at once.
    private func repeating(every interval: Duration, _ work: @escaping @MainActor @Sendable (Monitor) async -> Void) {
        tasks.append(Task { [weak self] in
            let clock = ContinuousClock()
            var next = clock.now
            while !Task.isCancelled {
                guard let self else { return }
                await work(self)
                next = max(next + interval, clock.now)
                try? await Task.sleep(until: next, clock: clock)
            }
        })
    }

    private func publish() {
        now = Date().timeIntervalSince1970
        measurements.advance(now: now)
        snapshot = measurements.snapshot(now: now)
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

    private var settled: Bool { settle.ready(at: Date().timeIntervalSince1970) }

    /// Waits, up to `limit` seconds, for the path to settle.
    private func whenSettled(limit: Double = 15) async -> Bool {
        let end = Date().timeIntervalSince1970 + limit
        while !settled, Date().timeIntervalSince1970 < end, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return settled
    }

    private func probeOnce(start: Double) async {
        // spec rules/probe-stats.md: no network path, no Probes; the Verdict says Offline.
        // A path that hasn't settled isn't measured yet (ADR 0013).
        guard path.satisfied, settled else { return publish() }
        await refreshNames()
        // Results belong to the Link they were sent on, even if the path changes mid-flight.
        let link = path.link
        let timeout = timeout(intervalMs: group.latencyMs)
        let jobs = group.probes.compactMap { probe in
            address(of: probe.target).flatMap { addr in
                runners.first { $0.handles(probe) }.map { (probe, addr, $0) }
            }
        }
        let outcomes = await withTaskGroup(of: (Probe, Measurements.Outcome).self) { group in
            for (probe, addr, runner) in jobs {
                group.addTask { (probe, await runner.run(probe, address: addr, timeout: timeout)) }
            }
            var out: [(Probe, Measurements.Outcome)] = []
            for await result in group { out.append(result) }
            return out
        }
        // A Round the path changed under measured the switch, not the network (ADR 0013). One a
        // Pause cut records nothing: Measurements decides that from its start and end.
        if !Task.isCancelled, settled {
            measurements.commit(.init(start: start, end: Date().timeIntervalSince1970, link: link, outcomes: outcomes))
        }
        publish()
    }

    private func checkCaptivePortal() async {
        guard path.satisfied, await whenSettled() else { return }
        let link = path.link
        // No answer at all isn't a portal: keep the last known state.
        guard let portal = await CaptivePortalCheck.run(defaults.captivePortalURL) else { return }
        measurements.setCaptivePortal(portal, checkedOn: link)
        publish()
    }

    private func lookUpPublicAddress() async {
        guard path.satisfied, await whenSettled() else { return }
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
        settle.report(.init(link: state.link, up: state.satisfied, ipv4: state.ipv4, ipv6: state.ipv6),
                      at: Date().timeIntervalSince1970)
        if measurements.setPath(link: state.link, up: state.satisfied, viaVPN: state.vpn, at: Date().timeIntervalSince1970) {
            Task { [weak self] in
                await self?.checkCaptivePortal()
                await self?.lookUpPublicAddress()
            }
        }
        publish()
    }

    private func sweepOnce(_ target: String) async {
        guard path.satisfied, settled, let addr = address(of: target) else { return }
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
        guard !Task.isCancelled, settled else { return }
        measurements.recordSweep(results, target: target, sentOn: link)
        lookUpNames(results.compactMap(\.addr))
    }
}

/// Keeps the app running long enough to finish a write after it leaves the foreground.
/// https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time
@MainActor
private final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
