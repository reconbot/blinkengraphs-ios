import BlinkengraphsCore
import Foundation

enum SpecResources {
    static let defaults: Defaults = load("defaults") { shared in
        try Defaults.decode(shared, override: data("defaults.override"))
    }
    static let tokens: Tokens = load("blinkengraphs.tokens", Tokens.decode)
    /// This app's light palette (ADR 0007).
    static let lightTokens: Tokens? = try? Tokens.decode(data("tokens.light"))
    /// The pinned spec's release, from release-please's manifest.
    /// Soft-fails to "unknown": Xcode may skip dot-files when copying resources.
    static let specVersion: String = Bundle.main.url(forResource: ".release-please-manifest", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }?["."] ?? "unknown"
    /// Every Target address in the Probe Group; a redacted report keeps these.
    static var targetAddresses: Set<String> {
        Set(defaults.probeGroup.targets.map(\.target).filter { $0.contains(".") || $0.contains(":") })
    }

    private static func load<T>(_ name: String, _ decode: (Data) throws -> T) -> T {
        guard let value = try? decode(data(name)) else { fatalError("\(name).json missing or invalid") }
        return value
    }

    private static func data(_ name: String) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { fatalError("\(name).json missing from the bundle; run `git submodule update --init`") }
        return data
    }
}
