import CoreTelephony
import Foundation
import Network

/// What `NWPathMonitor` says about the current route, reduced to what the app shows and uses.
struct PathState: Equatable, Sendable {
    var satisfied = false
    var interfaces: [String] = []
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

    init() {}

    init(_ path: NWPath) {
        satisfied = path.status == .satisfied
        interfaces = path.availableInterfaces.map { i in
            switch i.type {
            case .wifi: "Wi-Fi"
            case .cellular: "Cellular"
            case .wiredEthernet: "Ethernet"
            case .loopback: "Loopback"
            default: i.name
            }
        }
        gateway = path.gateways.lazy.compactMap { endpoint -> String? in
            guard case .hostPort(.ipv4(let a), _) = endpoint else { return nil }
            return a.rawValue.map(String.init).joined(separator: ".")
        }.first
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
