import BlinkengraphsCore
import Foundation

enum SpecResources {
    static let defaults: Defaults = load("defaults") { shared in
        try Defaults.decode(shared, override: data("defaults.override"))
    }
    static let tokens: Tokens = load("blinkengraphs.tokens", Tokens.decode)

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
