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
    /// Each Probe's results in its stats window, for the readouts.
    var window: [Probe: [ProbeResult]] = [:]
    /// The graphs' right edge, in the results' clock (seconds since 1970).
    var now: Double = Date().timeIntervalSince1970
    /// Raw, Archives and Pauses, for the graphs.
    var history: History?
    /// The Probe Group as shown: names, order, charted Probes, colour slots.
    var layout = TargetLayout(SpecResources.defaults.probeGroup)
    /// Measured now, stamped with the clock; demo data is fixed and doesn't scroll.
    var live = false
    var captivePortal = false
    var publicAddress: [IPFamily: PublicAddressReading] = [:]
    /// Every measured Link, the default-route one first, each judged on its own Probes.
    var links: [Measurements.LinkState] = []
    /// A cellular Link is there but the user hasn't turned on measuring it.
    var unmeasuredCellular = false
}

extension Link {
    /// What a person calls this Link. iPhones name Wi-Fi `en0`; extra `en` interfaces are wired.
    var kindName: String {
        if interface.hasPrefix("pdp_ip") { return "Cellular" }
        if interface.hasPrefix("utun") || interface.hasPrefix("ipsec") { return "VPN" }
        if interface == "en0" { return "Wi-Fi" }
        if interface.hasPrefix("en") { return "Ethernet" }
        return interface
    }

    /// The Section color the Link's line takes in Compare.
    var colorToken: String {
        switch kindName {
        case "Wi-Fi": "color.section.network"
        case "Cellular": "color.section.upload"
        case "VPN": "color.section.memory"
        default: "color.section.cpu"
        }
    }
}
