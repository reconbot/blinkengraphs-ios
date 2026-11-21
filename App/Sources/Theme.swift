import BlinkengraphsCore
import SwiftUI

extension EnvironmentValues {
    @Entry var tokens: Tokens = SpecResources.tokens
}

extension Tokens {
    func swiftUIColor(_ path: String) -> Color {
        guard let c = color(path) else { return .primary }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    func severity(_ s: Severity) -> Color {
        swiftUIColor("color.severity.\(s.rawValue.lowercased())")
    }
}
