import BlinkengraphsCore
import Charts
import SwiftUI

extension GraphRange {
    /// Gridlines, counted back from now: the step of the shortest fixed range that covers `span`.
    static func axisStep(span: Double) -> Double {
        switch span {
        case ...60: 20
        case ...900: 300
        case ...3600: 900
        case ...86_400: 21_600
        default: 86_400 * max(1, (span / 86_400 / 7).rounded(.up))
        }
    }
}

/// One Target's line, of its charted Probe (TargetLayout), drawn from one source per range
/// (spec rules/history.md, "Graph ranges").
struct Series: Identifiable {
    var target: String
    var probe: Probe
    var color: Color
    /// One per bucket with results or Paused, oldest first; a point's time is its bucket's start.
    var points: [GraphPoint]
    /// The graphs' right edge, which moves every refresh; buckets don't.
    var now: Double
    var span: Double
    var id: String { target }

    /// A point's time against `now`: negative seconds, sliding left as time passes.
    func x(_ p: GraphPoint) -> Double { Double(p.at) - now }

    /// Over the whole range, for the legend, in the chosen aggregate.
    var summary: Double?
    var aggregate: Aggregate
    var loss: Double

    /// The span every series of `range` shares, so All lines up across Targets: from the
    /// oldest A3 Row to now, at least a day.
    static func span(_ d: Dashboard, range: GraphRange) -> Double {
        if let span = range.span { return Double(span) }
        let oldest = d.history?.oldestDay.map(Double.init) ?? d.now
        return max(86_400, d.now - oldest)
    }

    static func all(_ d: Dashboard, range: GraphRange, palette: Palette, aggregate: Aggregate) -> [Series] {
        guard let history = d.history else { return [] }
        let span = span(d, range: range), now = Int(d.now.rounded(.down)), link = d.path.link
        return d.layout.charted.compactMap { entry in
            guard let probe = entry.charted else { return nil }
            let source = history.source(HistoryKey(link: link, probe: probe))
            let points = Graph.points(range, now: now, source: source, aggregate: aggregate)
            guard points.contains(where: { $0.state != .paused }) else { return nil }
            let summary = Graph.summary(range, now: now, source: source, aggregate: aggregate)
            return Series(target: entry.target, probe: probe, color: palette.series(entry.slot), points: points,
                          now: d.now, span: span, summary: summary.value, aggregate: aggregate, loss: summary.loss)
        }
    }
}

// MARK: - Latency

struct LatencyCard: View {
    let dashboard: Dashboard
    let series: [Series]
    @Binding var range: GraphRange
    /// Off while scrolling: the chart holds still under the finger.
    let animate: Bool
    @State private var hidden: Set<String> = []
    @Environment(\.palette) private var palette

    var body: some View {
        let all = series
        let shown = all.filter { !hidden.contains($0.target) }
        Card(title: "Latency", accent: palette.color("color.section.latency")) {
            RangePicker(range: $range)
        } content: {
            LatencyChart(series: shown, now: dashboard.now, span: Series.span(dashboard, range: range),
                         label: range.rawValue, animate: animate && dashboard.live)
                .frame(height: 190)
                .overlay {
                    if all.isEmpty {
                        Text(dashboard.path.satisfied ? "Collecting…" : "Paused: no network path")
                            .font(.footnote).foregroundStyle(palette.textWeak)
                    }
                }
            VStack(spacing: 2) {
                ForEach(all) { s in
                    LegendRow(series: s, jitter: dashboard.stats[s.probe]?.jitterMs, hidden: hidden.contains(s.target))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.smooth) {
                                if hidden.remove(s.target) == nil { hidden.insert(s.target) }
                            }
                        }
                        .sensoryFeedback(.selection, trigger: hidden.contains(s.target))
                }
            }
        }
    }
}

/// The gping-style chart, drawn with Canvas. A TimelineView moves the right edge with the clock,
/// so every point scrolls at one speed, frame by frame, however often data arrives. Swift Charts
/// animated mark by mark instead: points changed identity as gaps scrolled off and flew in and
/// out, and each 1 s animation stalled when a refresh took longer.
private struct LatencyChart: View {
    let series: [Series]
    /// When the data was taken.
    let now: Double
    let span: Double
    let label: String
    /// Scroll with the clock; off while the user scrolls and for fixed demo data.
    let animate: Bool
    @Environment(\.palette) private var palette

    private let leading: CGFloat = 30, bottom: CGFloat = 18

    var body: some View {
        let yMax = yMax, lines = lines, loss = worstLoss, paused = paused
        // About a pixel of movement per frame: 30 fps for 1m, rarely for 7d.
        TimelineView(.animation(minimumInterval: max(1.0 / 30, span / 600), paused: !animate)) { context in
            // Live data is stamped with the clock, so it never runs ahead of the edge.
            let edge = animate ? max(context.date.timeIntervalSince1970, now) : now
            Canvas { ctx, size in
                let plot = CGRect(x: leading, y: 4, width: max(1, size.width - leading), height: max(1, size.height - bottom - 4))
                drawGrid(&ctx, plot, yMax: yMax)
                var clipped = ctx
                clipped.clip(to: Path(plot))
                let x = { (t: Double) in plot.maxX - CGFloat((edge - t) / span) * plot.width }
                let y = { (v: Double) in plot.maxY - CGFloat(min(v, yMax) / yMax) * plot.height }
                // Before the first point there is no data (rules/history.md, "Drawing").
                if let first = series.compactMap({ $0.points.first?.at }).min(), Double(first) > edge - span {
                    clipped.fill(Path(CGRect(x: plot.minX, y: plot.minY, width: x(Double(first)) - plot.minX, height: plot.height)),
                                 with: .color(palette.cardEdge.opacity(0.35)))
                }
                // Paused: not measuring, never loss. A Pause is machine-wide, so every line shares it.
                for (start, width) in paused {
                    clipped.fill(Path(CGRect(x: x(start), y: plot.minY, width: max(1, x(start + width) - x(start)), height: plot.height)),
                                 with: .color(palette.cardEdge.opacity(0.7)))
                }
                // Loss along the floor, one tick per bucket at its worst Target's loss.
                for (start, width, l) in loss {
                    let r = CGRect(x: x(start), y: plot.maxY - plot.height * 0.06,
                                   width: max(1, x(start + width) - x(start)), height: plot.height * 0.06)
                    clipped.fill(Path(r), with: .color(palette.loss.opacity(0.25 + 0.75 * min(1, l * 2.5))))
                }
                for line in lines {
                    // The provisional edge can still change: drawn hollow.
                    if let p = line.provisional {
                        let c = CGPoint(x: x(p.t), y: y(p.v))
                        clipped.stroke(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)),
                                       with: .color(line.color), lineWidth: 1.5)
                    }
                    for run in line.runs {
                        if run.count == 1, let p = run.first {
                            let c = CGPoint(x: x(p.t), y: y(p.v))
                            clipped.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(line.color))
                            continue
                        }
                        var path = Path()
                        for (i, p) in run.enumerated() {
                            let pt = CGPoint(x: x(p.t), y: y(p.v))
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                        clipped.stroke(path, with: .color(line.color),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Latency over \(label == "All" ? "all history" : "the last \(label)")")
    }

    private struct Line { var color: Color; var runs: [[(t: Double, v: Double)]]; var provisional: (t: Double, v: Double)? }

    /// Each series as runs of closed points at bucket starts (rules/history.md, "Drawing"). A run
    /// breaks at a bucket with no point, a Paused one, and one whose results were all lost.
    private var lines: [Line] {
        series.map { s in
            var runs: [[(t: Double, v: Double)]] = [], run: [(t: Double, v: Double)] = []
            var provisional: (t: Double, v: Double)?
            var end = Int.min
            for p in s.points {
                if p.at > end || p.state != .value || p.provisional, !run.isEmpty { runs.append(run); run = [] }
                end = p.at + p.width
                guard p.state == .value, let v = p.value else { continue }
                if p.provisional { provisional = (Double(p.at), v) } else { run.append((Double(p.at), v)) }
            }
            if !run.isEmpty { runs.append(run) }
            return Line(color: s.color, runs: runs, provisional: provisional)
        }
    }

    private var paused: [(start: Double, width: Double)] {
        Set(series.flatMap { $0.points.filter { $0.state == .paused }.map { [$0.at, $0.width] } })
            .map { (Double($0[0]), Double($0[1])) }
    }

    private var worstLoss: [(start: Double, width: Double, loss: Double)] {
        var worst: [Int: (width: Int, loss: Double)] = [:]
        for s in series {
            for p in s.points where (p.loss ?? 0) > 0 {
                worst[p.at] = (p.width, max(worst[p.at]?.loss ?? 0, p.loss!))
            }
        }
        return worst.map { (Double($0.key), Double($0.value.width), $0.value.loss) }
    }

    /// Room above the busiest line, ignoring its rarest spikes; a round number, so the scale
    /// changes only when the data crosses one.
    private var yMax: Double {
        let values = series.flatMap { $0.points.compactMap(\.value) }.sorted()
        guard !values.isEmpty else { return 50 }
        let p98 = values[Int(Double(values.count - 1) * 0.98)]
        return GraphScale.niceCeiling(max(10, p98 * 1.15))
    }

    /// Fixed gridlines: ages are measured back from the edge, so they hold still as data scrolls.
    private func drawGrid(_ ctx: inout GraphicsContext, _ plot: CGRect, yMax: Double) {
        let grid = GraphicsContext.Shading.color(palette.cardEdge)
        let step = GraphScale.niceCeiling(yMax / 4)
        var v = 0.0
        while v <= yMax + 0.001 {
            let y = plot.maxY - CGFloat(v / yMax) * plot.height
            ctx.stroke(Path { $0.move(to: CGPoint(x: plot.minX, y: y)); $0.addLine(to: CGPoint(x: plot.maxX, y: y)) },
                       with: grid, lineWidth: 0.5)
            ctx.draw(Text("\(Int(v))").font(.caption2).foregroundStyle(palette.textWeak),
                     at: CGPoint(x: plot.minX - 4, y: y), anchor: .trailing)
            v += step
        }
        let ageStep = GraphRange.axisStep(span: span)
        var age = 0.0
        while age <= span + 0.001 {
            let x = plot.maxX - CGFloat(age / span) * plot.width
            ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: plot.minY)); $0.addLine(to: CGPoint(x: x, y: plot.maxY)) },
                       with: grid, style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            ctx.draw(Text(axisLabel(-age)).font(.caption2).foregroundStyle(palette.textWeak),
                     at: CGPoint(x: x, y: plot.maxY + 3), anchor: age == 0 ? .topTrailing : age >= span - 0.001 ? .topLeading : .top)
            age += ageStep
        }
    }

    /// In the unit of the range's gridline step, so 7d reads -1d, not -24h.
    private func axisLabel(_ s: Double) -> String {
        let a = -s
        if a == 0 { return "now" }
        switch GraphRange.axisStep(span: span) {
        case ..<60: return "-\(Int(a))s"
        case ..<3600: return "-\(Int(a / 60))m"
        case ..<86_400: return "-\(Int(a / 3600))h"
        default: return "-\(Int(a / 86_400))d"
        }
    }
}

private struct LegendRow: View {
    let series: Series
    let jitter: Double?
    let hidden: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(hidden ? Color.clear : series.color)
                .overlay(Circle().strokeBorder(series.color, lineWidth: 1.5))
                .frame(width: 9, height: 9)
            Text(TargetLayout.name(series.target))
                .foregroundStyle(hidden ? palette.textWeak : palette.text)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Text("\(series.aggregate.label) \(ms(series.summary)) ms").foregroundStyle(palette.text)
            Text(percent(series.loss))
                .foregroundStyle(percent(series.loss) != "0%" ? palette.loss : palette.textWeak)
                .frame(width: 38, alignment: .trailing)
            Text(jitter.map { "±\(ms($0))" } ?? "")
                .foregroundStyle(palette.textWeak)
                .frame(width: 44, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .padding(.vertical, 3)
        .opacity(hidden ? 0.6 : 1)
    }
}

struct RangePicker: View {
    @Binding var range: GraphRange
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(GraphRange.allCases) { r in
                Button(r.rawValue) { withAnimation(.smooth) { range = r } }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(range == r ? palette.text : palette.textWeak)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background { if range == r { Capsule().fill(palette.cardEdge) } }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: range)
    }
}

// MARK: - Targets

struct TargetGrid: View {
    let dashboard: Dashboard
    let series: [Series]

    var body: some View {
        let byTarget = Dictionary(grouping: Set(dashboard.stats.keys).union(dashboard.denied), by: \.target)
        let entries = dashboard.layout.entries.filter { byTarget[$0.target] != nil }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
            ForEach(entries) { entry in
                TargetCard(entry: entry, dashboard: dashboard, series: series.first { $0.target == entry.target })
            }
        }
    }
}

private struct TargetCard: View {
    @AppStorage(Aggregate.readoutStorageKey) private var aggregate = SpecResources.defaults.readoutAggregate
    let entry: TargetLayout.Entry
    let dashboard: Dashboard
    let series: Series?
    @Environment(\.palette) private var palette

    var body: some View {
        let target = entry.target
        // Probes that have reported, in the layout's order.
        let sorted = entry.probes.filter { dashboard.stats[$0] != nil || dashboard.denied.contains($0) }
        let lead = sorted.first.flatMap { dashboard.stats[$0] }
        let leadValue = sorted.first.flatMap(readout)
        let accent = series?.color ?? palette.series(entry.slot)
        Card(title: entry.name, accent: accent) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(ms(leadValue))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.text)
                    // p95 readouts reach three digits; shrink rather than wrap beside the loss badge.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                // The readout names its aggregate unless it is the median (rules/probe-stats.md).
                Text(aggregate == .p50 ? "ms" : "ms \(aggregate.label)").font(.caption).foregroundStyle(palette.textWeak)
                Spacer()
                if let loss = lead?.loss, loss > 0 {
                    Text(percent(loss))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.loss)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(palette.loss.opacity(0.15)))
                }
            }
            .monospacedDigit()
            if target == Probe.gateway, let gw = dashboard.path.gateway {
                Text(gw).font(.caption).foregroundStyle(palette.textWeak).lineLimit(1).padding(.top, -8)
            }
            if let series { Sparkline(series: series).frame(height: 34) }
            VStack(spacing: 4) {
                ForEach(sorted, id: \.self) { p in
                    HStack {
                        Text(label(p)).foregroundStyle(palette.textWeak)
                        Spacer()
                        value(p)
                    }
                }
            }
            .font(.caption)
            .monospacedDigit()
        }
        .animation(.smooth, value: leadValue)
    }

    @ViewBuilder private func value(_ p: Probe) -> some View {
        if dashboard.denied.contains(p) {
            // Not a loss: the OS refused to send it (rules/probe-stats.md).
            Text("LAN denied").foregroundStyle(palette.severity(.warn))
        } else if let s = dashboard.stats[p] {
            HStack(spacing: 6) {
                if s.loss > 0 { Text(percent(s.loss)).foregroundStyle(palette.loss) }
                Text("\(ms(readout(p))) ms").foregroundStyle(palette.text)
            }
        }
    }

    /// spec rules/probe-stats.md, "Readouts": the chosen aggregate of the Probe's window.
    private func readout(_ p: Probe) -> Double? {
        guard let stats = dashboard.stats[p] else { return nil }
        return Readout.value(dashboard.window[p] ?? [], stats: stats, aggregate: aggregate, now: dashboard.now,
                             windowSeconds: Double(SpecResources.defaults.history.recentWindowS))
    }

    private func label(_ p: Probe) -> String {
        let parts = p.protocol.split(separator: ":")
        return parts.map { $0.uppercased() }.joined(separator: " ")
    }
}

private struct Sparkline: View {
    let series: Series

    var body: some View {
        let values = series.points.compactMap(\.value)
        let top = GraphScale.niceCeiling(max(values.max() ?? 1, 1) * 1.1)
        Chart {
            ForEach(series.points.filter { $0.value != nil }, id: \.at) { p in
                AreaMark(x: .value("t", series.x(p)), y: .value("ms", p.value!))
                    .foregroundStyle(LinearGradient(colors: [series.color.opacity(0.35), series.color.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", series.x(p)), y: .value("ms", p.value!))
                    .foregroundStyle(series.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
                if values.count == 1 {
                    PointMark(x: .value("t", series.x(p)), y: .value("ms", p.value!))
                        .foregroundStyle(series.color).symbolSize(16)
                }
            }
        }
        .chartXScale(domain: -series.span...0)
        .chartPlotStyle { $0.clipped() }
        // No scroll animation: six sparklines gliding every second cost more than they showed.
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}

// MARK: - Hop Trace

struct HopTraceCard: View {
    let target: String
    let rows: [HopRow]
    let names: [String: String]
    @Environment(\.palette) private var palette

    var body: some View {
        let (shown, silent) = HopTrace.collapsingSilentTail(rows)
        let worst = max(shown.compactMap(\.avgMs).max() ?? 1, 1)
        Card(title: "Hop Trace", accent: palette.color("color.section.network")) {
            Text(target).font(.caption).foregroundStyle(palette.textWeak).lineLimit(1).truncationMode(.middle)
        } content: {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("#")
                    Text("Host").gridColumnAlignment(.leading)
                    Text("Loss"); Text("Avg"); Text("Best"); Text("Wrst")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.textWeak)
                ForEach(shown, id: \.ttl) { row in
                    GridRow {
                        Text("\(row.ttl)").foregroundStyle(palette.textWeak)
                        host(row, worst: worst)
                        Text(row.addr == nil ? "" : percent(row.loss))
                            .foregroundStyle(row.loss > 0 ? palette.loss : palette.textWeak)
                        Text(ms(row.avgMs)); Text(ms(row.bestMs)); Text(ms(row.worstMs))
                    }
                    .foregroundStyle(palette.text)
                }
            }
            .font(.caption)
            .monospacedDigit()
            if let silent {
                Text("Hops \(silent.lowerBound)–\(silent.upperBound): no reply")
                    .font(.caption).foregroundStyle(palette.textWeak)
            }
        }
    }

    /// Like mtr: the name when reverse DNS has one, the address beneath it, and a bar for average latency.
    private func host(_ row: HopRow, worst: Double) -> some View {
        let name = row.addr.flatMap { names[$0] }
        return VStack(alignment: .leading, spacing: 2) {
            Text(name ?? row.addr ?? "no reply")
                .foregroundStyle(row.addr == nil ? palette.textWeak : palette.text)
                .lineLimit(1).truncationMode(.middle)
            if name != nil, let addr = row.addr {
                Text(addr).font(.caption2).foregroundStyle(palette.textWeak).lineLimit(1).truncationMode(.middle)
            }
            if let avg = row.avgMs {
                GeometryReader { g in
                    Capsule()
                        .fill(row.loss > 0 ? palette.loss : palette.color("color.section.network"))
                        .frame(width: max(3, g.size.width * avg / worst))
                }
                .frame(height: 3)
                .opacity(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
