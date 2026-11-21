import BlinkengraphsCore
import SwiftUI
import WidgetKit

@main
struct BlinkengraphsWidgets: WidgetBundle {
    var body: some Widget { VerdictWidget() }
}

struct VerdictWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Verdict", provider: VerdictProvider()) { entry in
            VerdictWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { SpecResources.tokens.swiftUIColor("color.surface.background") }
        }
        .configurationDisplayName("Verdict")
        .description("The last Verdict from blinkengraphs.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct VerdictEntry: TimelineEntry {
    let date: Date
    let snapshot: VerdictSnapshot?
}

/// One entry and no schedule: the app reloads the timeline when the Findings change.
struct VerdictProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerdictEntry {
        VerdictEntry(date: .now, snapshot: VerdictSnapshot(at: .now, findings: [
            Finding(domain: .clear, severity: .ok, headline: "All clear"),
        ]))
    }

    func getSnapshot(in context: Context, completion: @escaping (VerdictEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VerdictEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> VerdictEntry {
        VerdictEntry(date: .now, snapshot: AppGroup.snapshotStore?.load())
    }
}

struct VerdictWidgetView: View {
    let snapshot: VerdictSnapshot?
    @Environment(\.widgetFamily) private var family
    private let tokens = SpecResources.tokens

    var body: some View {
        if let snapshot, let top = snapshot.findings.first {
            switch family {
            case .accessoryInline:
                Label(top.headline, systemImage: top.severity.symbol)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label(top.headline, systemImage: top.severity.symbol)
                        .font(.headline)
                        .foregroundStyle(tokens.severity(top.severity))
                    if snapshot.findings.count > 1 {
                        Text("+\(snapshot.findings.count - 1) more")
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                    // Stale on purpose: the widget shows the last Verdict, not a live one.
                    Text(snapshot.at, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(tokens.swiftUIColor("color.surface.text-weak"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Open blinkengraphs to measure")
                .font(.caption)
        }
    }
}
