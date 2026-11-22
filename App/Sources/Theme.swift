import BlinkengraphsCore
import SwiftUI
import UIKit

/// The spec's tokens and its light palette; every color follows the system appearance.
/// A path the light palette lacks keeps its base (dark) value (spec tokens/README.md).
struct Palette: Sendable {
    var dark: Tokens
    var light: Tokens?

    func color(_ path: String) -> Color {
        let dark = dark.color(path), light = light?.color(path) ?? dark
        guard let dark, let light else { return .primary }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .light ? light.uiColor : dark.uiColor })
    }

    func severity(_ s: Severity) -> Color { color("color.severity.\(s.rawValue.lowercased())") }

    var background: Color { color("color.surface.background") }
    var card: Color { color("color.surface.card") }
    var cardEdge: Color { color("color.surface.card-edge") }
    var text: Color { color("color.surface.text") }
    var textWeak: Color { color("color.surface.text-weak") }
    var loss: Color { color("color.loss") }

    /// One color per charted Target, in Probe Group order; borrowed from the Section colors.
    func series(_ index: Int) -> Color {
        let order = ["network", "latency", "upload", "memory", "disk", "cpu"]
        return color("color.section.\(order[index % order.count])")
    }
}

extension EnvironmentValues {
    @Entry var palette = Palette(dark: SpecResources.tokens, light: SpecResources.lightTokens)
}

private extension RGB {
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
}
