import BlinkengraphsCore
import Foundation
import Observation
import WidgetKit

/// Runs the Probe Group's Probes on the latency interval and keeps the Verdict current.
@MainActor @Observable
final class Monitor {
    private(set) var stats: [Probe: ProbeStats] = [:]
    private(set) var verdict: [Finding] = Verdict.evaluate(VerdictInput(probes: []))

    private let defaults: Defaults
    private let runners: [any ProbeRunner] = [TCPProbeRunner()]
    private var histories: [Probe: ProbeHistory] = [:]
    private var task: Task<Void, Never>?

    init(defaults: Defaults) { self.defaults = defaults }

    func start() {
        guard task == nil else { return }
        let interval = defaults.probeGroup.latencyMs
        let timeout = Duration.milliseconds(defaults.probeTimeoutMs(intervalMs: interval))
        let probes = defaults.probeGroup.probes.compactMap { p in
            runners.first { $0.handles(p) }.map { (p, $0) }
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await withTaskGroup(of: (Probe, ProbeOutcome).self) { group in
                    for (probe, runner) in probes {
                        group.addTask { (probe, await runner.run(probe, timeout: timeout)) }
                    }
                    for await (probe, outcome) in group { self?.record(probe, outcome) }
                }
                self?.refreshVerdict()
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func record(_ probe: Probe, _ outcome: ProbeOutcome) {
        let at = Date().timeIntervalSince1970
        let result: ProbeResult
        switch outcome {
        case .reply(let ms): result = ProbeResult(at: at, rttMs: ms)
        case .lost: result = ProbeResult(at: at, rttMs: nil)
        case .denied: return // rules/probe-stats.md: not a loss, not recorded.
        }
        histories[probe, default: ProbeHistory(ramSeconds: Double(defaults.history.ramMinutes * 60))].record(result)
    }

    private func refreshVerdict() {
        let window = Double(defaults.history.recentWindowS)
        stats = histories.mapValues { $0.stats(windowSeconds: window) }
        verdict = Verdict.evaluate(VerdictInput(probes: stats.map { .init(probe: $0.key, stat: $0.value) }))
        // WidgetKit budgets reloads, so ask for one only when the Findings change.
        if AppGroup.snapshotStore?.save(VerdictSnapshot(at: .now, findings: verdict)) == true {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
