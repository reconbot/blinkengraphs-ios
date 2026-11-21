import BlinkengraphsCore
import Foundation

enum SpecResources {
    static let defaults: Defaults = load("defaults", Defaults.decode)
    static let tokens: Tokens = load("blinkengraphs.tokens", Tokens.decode)

    private static func load<T>(_ name: String, _ decode: (Data) throws -> T) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let value = try? decode(Data(contentsOf: url))
        else { fatalError("\(name).json missing from the bundle; run `git submodule update --init`") }
        return value
    }
}
