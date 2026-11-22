import BlinkengraphsCore
import Foundation

/// Everything the screen shows, as one value: from the live Monitor or a demo scenario.
struct Dashboard: Sendable {
    var findings: [Finding] = Verdict.evaluate(VerdictInput(probes: []))
    var stats: [Probe: ProbeStats] = [:]
    var denied: Set<Probe> = []
    var path = PathState()
    var hops: [String: [HopRow]] = [:]
    var hopNames: [String: String] = [:]
    /// Each Probe's RAM History on the current Link, for the graphs.
    var results: [Probe: [ProbeResult]] = [:]
    /// The graphs' right edge, in the results' clock (seconds since 1970).
    var now: Double = Date().timeIntervalSince1970
    /// Rollups for the longer graphs; nil before any exist.
    var history: RollupHistory?
    /// The Probe Group as shown: names, order, charted Probes, colour slots.
    var layout = TargetLayout(SpecResources.defaults.probeGroup)
    /// Measured now, stamped with the clock; demo data is fixed and doesn't scroll.
    var live = false
    var captivePortal = false
    var publicAddress: [IPFamily: PublicAddressReading] = [:]
}
