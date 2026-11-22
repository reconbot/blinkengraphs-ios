import BlinkengraphsCore
import CoreTelephony
import Foundation
import Network

/// What `NWPathMonitor` says about the current route, reduced to what the app shows and uses.
struct PathState: Equatable, Sendable {
    /// Up until NWPathMonitor says otherwise, so launch doesn't flash Offline.
    var satisfied = true
    var interfaces: [String] = []
    /// BSD name of the preferred interface (en0, pdp_ip0); with the Gateway it names the Link.
    var interfaceName: String?
    /// The Gateway's IPv4 address, when the path has one.
    var gateway: String?
    var expensive = false
    var constrained = false
    var ipv4 = false
    var ipv6 = false
    var dns = false
    /// iOS 26+: Apple's coarse rating of the link layer. Only for display; Apple says not to gate on it.
    var linkQuality: String?
    /// LTE, 5G and so on, when the path uses cellular.
    var radio: String?
    /// The preferred interface is a tunnel: a VPN app, iCloud Private Relay or a Tailscale exit node.
    var vpn = false

    init() {}

    var link: Link { Link(interface: interfaceName ?? "none", gateway: gateway) }

    /// One entry per interface kind, in preference order. iOS lists every interface it could use,
    /// several cellular ones among them, and a VPN app's tunnel even when it carries nothing, so
    /// VPN appears only when traffic goes through it. The chips and the report both read this.
    var shownInterfaces: [String] {
        var seen = Set<String>()
        return interfaces.filter { ($0 != "VPN" || vpn) && seen.insert($0).inserted }
            .map { $0 == "Cellular" ? ["Cellular", radio].compactMap { $0 }.joined(separator: " ") : $0 }
    }

    /// The connection as labelled facts, for the report; the chips show the same facts.
    var facts: [(label: String, value: String)] {
        var out: [(String, String)] = [
            ("Path", satisfied ? "Up" : "Down"),
            ("Via", satisfied ? shownInterfaces.joined(separator: " · ").nonEmpty ?? "—" : "—"),
            ("Supports", [ipv4 ? "IPv4" : nil, ipv6 ? "IPv6" : nil, dns ? "DNS" : nil].compactMap { $0 }.joined(separator: ", ")),
            ("Gateway", gateway ?? "—"),
        ]
        if let linkQuality { out.append(("Link quality", linkQuality)) }
        if expensive { out.append(("Metered", "yes")) }
        if constrained { out.append(("Low Data", "yes")) }
        return out
    }

    init(_ path: NWPath) {
        satisfied = path.status == .satisfied
        interfaces = path.availableInterfaces.map { i in
            switch i.type {
            case .wifi: "Wi-Fi"
            case .cellular: "Cellular"
            case .wiredEthernet: "Ethernet"
            case .loopback: "Loopback"
            // utun and ipsec are tunnels: a VPN or iCloud Private Relay.
            default: i.name.hasPrefix("utun") || i.name.hasPrefix("ipsec") ? "VPN" : i.name
            }
        }
        interfaceName = path.availableInterfaces.first?.name
        vpn = interfaceName.map { $0.hasPrefix("utun") || $0.hasPrefix("ipsec") } ?? false
        gateway = Self.gateway(of: path)
        expensive = path.isExpensive
        constrained = path.isConstrained
        ipv4 = path.supportsIPv4
        ipv6 = path.supportsIPv6
        dns = path.supportsDNS
        if #available(iOS 26, *) {
            switch path.linkQuality {
            case .good: linkQuality = "Good"
            case .moderate: linkQuality = "Moderate"
            case .minimal: linkQuality = "Minimal"
            default: linkQuality = nil
            }
        }
        if path.usesInterfaceType(.cellular) { radio = Self.currentRadio() }
    }

    /// The path's IPv4 Gateway, when it is a router (not a 464XLAT translator).
    static func gateway(of path: NWPath) -> String? {
        path.gateways.lazy.compactMap { endpoint -> String? in
            guard case .hostPort(.ipv4(let a), _) = endpoint else { return nil }
            let ip = a.rawValue.map(String.init).joined(separator: ".")
            return Gateway.isRouter(ip) ? ip : nil
        }.first
    }

    /// The data SIM's radio technology. Cell ID and signal strength have no public API.
    private static func currentRadio() -> String? {
        let info = CTTelephonyNetworkInfo()
        guard let techs = info.serviceCurrentRadioAccessTechnology else { return nil }
        let tech = info.dataServiceIdentifier.flatMap { techs[$0] } ?? techs.values.first
        switch tech {
        case CTRadioAccessTechnologyNR: return "5G"
        case CTRadioAccessTechnologyNRNSA: return "5G NSA"
        case CTRadioAccessTechnologyLTE: return "LTE"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD: return "3G"
        case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyCDMA1x: return "2G"
        default: return nil
        }
    }
}

final class PathWatcher: Sendable {
    private let monitor = NWPathMonitor()

    func start(_ onChange: @escaping @Sendable (PathState) -> Void) {
        monitor.pathUpdateHandler = { onChange(PathState($0)) }
        monitor.start(queue: DispatchQueue(label: "blinkengraphs.path"))
    }

    func stop() { monitor.cancel() }
}

/// One active Link besides the default route, as its own typed path monitor sees it.
struct LinkPath: Equatable, Sendable {
    enum Kind: String, Sendable { case wifi = "Wi-Fi", cellular = "Cellular", wired = "Ethernet" }
    var kind: Kind
    var link: Link
    /// For IP_BOUND_IF: Probes on this Link leave through this interface.
    var index: UInt32
    var gateway: String?
    var ipv4: Bool
    var ipv6: Bool
}

/// Watches each interface type on its own (docs/research/multi-link-probing.md, section 3), so
/// cellular is seen while Wi-Fi carries the default route.
final class LinkWatcher: Sendable {
    private let monitors: [(LinkPath.Kind, NWPathMonitor)] = [
        (.wifi, NWPathMonitor(requiredInterfaceType: .wifi)),
        (.cellular, NWPathMonitor(requiredInterfaceType: .cellular)),
        (.wired, NWPathMonitor(requiredInterfaceType: .wiredEthernet)),
    ]

    /// Reports each kind's Link, or nil when that kind has no working path.
    func start(_ onChange: @escaping @Sendable (LinkPath.Kind, LinkPath?) -> Void) {
        for (kind, monitor) in monitors {
            monitor.pathUpdateHandler = { path in
                guard path.status == .satisfied, let i = path.availableInterfaces.first else { return onChange(kind, nil) }
                let gateway = PathState.gateway(of: path)
                onChange(kind, LinkPath(kind: kind, link: Link(interface: i.name, gateway: gateway), index: UInt32(i.index),
                                        gateway: gateway, ipv4: path.supportsIPv4, ipv6: path.supportsIPv6))
            }
            monitor.start(queue: DispatchQueue(label: "blinkengraphs.link.\(kind.rawValue)"))
        }
    }

    func stop() { monitors.forEach { $0.1.cancel() } }
}
