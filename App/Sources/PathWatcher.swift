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
