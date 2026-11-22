import BlinkengraphsCore
import Charts
import SwiftUI

/// What the history graphs span, as the Windows Panel offers. Up to 15 minutes comes from the RAM
/// History's raw samples, longer from Rollups (spec defaults.json `history`).
enum GraphRange: String, CaseIterable, Identifiable {
    case oneMinute = "1m", fifteenMinutes = "15m", oneHour = "1h", oneDay = "24h", sevenDays = "7d"
    var id: Self { self }
    var seconds: Double {
        switch self {
        case .oneMinute: 60
        case .fifteenMinutes: 900
        case .oneHour: 3600
        case .oneDay: 86_400
        case .sevenDays: 604_800
        }
    }
    /// Rollups hold whole minutes; with 60 buckets every longer range's buckets are whole minutes.
    var usesRollups: Bool { seconds > 900 }
    /// Gridlines, counted back from now.
    var axisStep: Double {
        switch self {
        case .oneMinute: 20
        case .fifteenMinutes: 300
        case .oneHour: 900
        case .oneDay: 21_600
        case .sevenDays: 86_400
        }
    }
    var buckets: Int { 60 }
    var bucketWidth: Double { seconds / Double(buckets) }

    /// Bucket edges fixed to the clock, so only the newest bucket changes between refreshes.
    func window(now: Double) -> ClosedRange<Double> {
        GraphBuckets.alignedRange(now: now, span: seconds, count: buckets)
    }
}

/// One Target's line: its ICMP Probe, else its first Probe.
struct Series: Identifiable {
    var target: String
    var probe: Probe
    var color: Color
    var points: [GraphPoint]
    /// The graphs' right edge, which moves every refresh; buckets don't.
    var now: Double
    var range: GraphRange
    var id: String { target }

    /// A bucket's middle against `now`: negative seconds, sliding left as time passes.
    func x(_ p: GraphPoint) -> Double { p.start + range.bucketWidth / 2 - now }

    /// Over the whole range, for the legend, in the chosen aggregate.
    var summary: Double?
    var aggregate: Aggregate
    var loss: Double

    @MainActor
    static func all(_ d: Dashboard, range: GraphRange, palette: Palette, aggregate: Aggregate) -> [Series] {
        let targets = SpecResources.defaults.probeGroup.targets.map(\.target).filter { $0 != Probe.systemDNS }
        return targets.enumerated().compactMap { i, target in
            let probe = Probe(target: target, protocol: "icmp")
            let window = range.window(now: d.now)
            if range.usesRollups {
                guard let rollups = d.history?.rollups else { return nil }
                let points = rollups.points(probe, on: d.path.link, from: window.lowerBound - range.bucketWidth,
                                            to: window.upperBound, count: range.buckets + 1, aggregate: aggregate)
                guard points.contains(where: { $0.count > 0 }) else { return nil }
                let summary = rollups.summary(probe, on: d.path.link, from: d.now - range.seconds, to: d.now + 60,
                                              aggregate: aggregate)
                return Series(target: target, probe: probe, color: palette.series(i), points: points,
                              now: d.now, range: range, summary: summary.value, aggregate: aggregate,
                              loss: summary.loss)
            }
            guard let results = d.results[probe], !results.isEmpty else { return nil }
            let inRange = results.filter { $0.at > d.now - range.seconds }
            let replies = inRange.compactMap(\.rttMs)
            return Series(
                target: target, probe: probe, color: palette.series(i),
                // One bucket more on the left, so the line runs to the edge as it scrolls.
                points: GraphBuckets.points(results, from: window.lowerBound - range.bucketWidth,
                                            to: window.upperBound, count: range.buckets + 1, aggregate: aggregate),
                now: d.now, range: range,
                summary: aggregate.value(ofSamples: replies), aggregate: aggregate,
                loss: inRange.isEmpty ? 0 : 1 - Double(replies.count) / Double(inRange.count))
        }
    }
}

/// How often the Monitor refreshes; graph animations last this long so motion is continuous.
let refreshSeconds = Double(SpecResources.defaults.probeGroup.latencyMs) / 1000

// MARK: - Latency

struct LatencyCard: View {
    @AppStorage(Aggregate.storageKey) private var aggregate = SpecResources.defaults.graphAggregate
    let dashboard: Dashboard
    @Binding var range: GraphRange
    @State private var hidden: Set<String> = []
    @Environment(\.palette) private var palette

    var body: some View {
        let all = Series.all(dashboard, range: range, palette: palette, aggregate: aggregate)
        let shown = all.filter { !hidden.contains($0.target) }
        Card(title: "Latency", accent: palette.color("color.section.latency")) {
            RangePicker(range: $range)
        } content: {
            LatencyChart(series: shown, now: dashboard.now, range: range)
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

private struct LatencyChart: View {
    let series: [Series]
    let now: Double
    let range: GraphRange
    @Environment(\.palette) private var palette

    private struct Plot: Identifiable {
        var id: String { "\(key)@\(start)" }
        /// The bucket's start: stable across refreshes, so Charts animates a point instead of replacing it.
        var start: Double
        var key: String
        var x: Double
        var y: Double
        var color: Color
        var loss: Double
    }

    var body: some View {
        let yMax = yMax
        let (lines, dots) = plots(yMax: yMax)
        let lonely = Set(Dictionary(grouping: lines, by: \.key).filter { $0.value.count == 1 }.keys)
        Chart {
            ForEach(lines) { p in
                // A wide, faint stroke under the line reads as a glow on the dark surface.
                // Monotone: smooth without overshooting a bucket's value.
                LineMark(x: .value("Time", p.x), y: .value("ms", p.y), series: .value("Glow", "g" + p.key))
                    .foregroundStyle(p.color.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.x), y: .value("ms", p.y), series: .value("Line", p.key))
                    .foregroundStyle(p.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            // A run of one bucket draws no line; a dot keeps fresh or gappy history visible.
            ForEach(lines.filter { lonely.contains($0.key) }) { p in
                PointMark(x: .value("Time", p.x), y: .value("ms", p.y))
                    .foregroundStyle(p.color)
                    .symbolSize(18)
            }
            // Loss as a strip along the floor, one tick per bucket at its worst Target's loss:
            // per-line dots buried the lines whenever every Target was losing.
            ForEach(dots) { d in
                RectangleMark(xStart: .value("Time", d.x - width / 2), xEnd: .value("Time", d.x + width / 2),
                              yStart: .value("ms", 0), yEnd: .value("ms", yMax * 0.06))
                    .foregroundStyle(palette.loss.opacity(0.25 + 0.75 * min(1, d.loss * 2.5)))
            }
        }
        .chartXScale(domain: -range.seconds...0)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, through: -range.seconds, by: -range.axisStep))) { v in
                AxisGridLine().foregroundStyle(palette.cardEdge)
                AxisValueLabel {
                    if let s = v.as(Double.self) {
                        Text(axisLabel(s)).foregroundStyle(palette.textWeak)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(palette.cardEdge)
                AxisValueLabel {
                    if let ms = v.as(Double.self) { Text("\(Int(ms))").foregroundStyle(palette.textWeak) }
                }
            }
        }
        .chartLegend(.hidden)
        .monospacedDigit()
        .chartPlotStyle { $0.clipped() }
        .animation(.smooth(duration: 0.4), value: series.map(\.target))
        .animation(.smooth(duration: 0.5), value: yMax)
        // Linear over one refresh interval: the lines glide left continuously, as in gping.
        .animation(.linear(duration: refreshSeconds), value: now)
    }

    private func axisLabel(_ s: Double) -> String {
        let a = -s
        if a == 0 { return "now" }
        if a < 120 { return "-\(Int(a))s" }
        if a < 7200 { return "-\(Int(a / 60))m" }
        if a < 172_800 { return "-\(Int(a / 3600))h" }
        return "-\(Int(a / 86_400))d"
    }

    /// Room above the busiest line, ignoring its rarest spikes; a round number, so the scale
    /// changes only when the data crosses one.
    private var yMax: Double {
        let values = series.flatMap { $0.points.compactMap(\.value) }.sorted()
        guard !values.isEmpty else { return 50 }
        let p98 = values[Int(Double(values.count - 1) * 0.98)]
        return GraphBuckets.niceCeiling(max(10, p98 * 1.15))
    }

    private var width: Double { range.bucketWidth }

    /// Lines broken at buckets with no reply, and each bucket's worst loss across the shown Targets.
    private func plots(yMax: Double) -> ([Plot], [Plot]) {
        var lines: [Plot] = [], worstLoss: [Double: Double] = [:]
        for s in series {
            var segment = 0
            for p in s.points {
                let x = s.x(p)
                if let v = p.value {
                    lines.append(Plot(start: p.start, key: "\(s.target)#\(segment)", x: x, y: min(v, yMax),
                                      color: s.color, loss: p.loss))
                } else {
                    segment += 1
                }
                if p.loss > 0 { worstLoss[p.start] = max(worstLoss[p.start] ?? 0, p.loss) }
            }
        }
        let dots = worstLoss.map { start, loss in
            Plot(start: start, key: "loss", x: start + width / 2 - now, y: 0, color: palette.loss, loss: loss)
        }
        return (lines, dots)
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
            Text(targetName(series.target))
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
    @AppStorage(Aggregate.storageKey) private var aggregate = SpecResources.defaults.graphAggregate
    let dashboard: Dashboard
    let range: GraphRange
    @Environment(\.palette) private var palette

    var body: some View {
        let series = Series.all(dashboard, range: range, palette: palette, aggregate: aggregate)
        let byTarget = Dictionary(grouping: Set(dashboard.stats.keys).union(dashboard.denied), by: \.target)
        let targets = SpecResources.defaults.probeGroup.targets.map(\.target).filter { byTarget[$0] != nil }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
            ForEach(targets, id: \.self) { target in
                TargetCard(target: target, probes: byTarget[target] ?? [], dashboard: dashboard,
                           series: series.first { $0.target == target })
            }
        }
    }
}

private struct TargetCard: View {
    @AppStorage(Aggregate.readoutStorageKey) private var aggregate = SpecResources.defaults.readoutAggregate
    let target: String
    let probes: [Probe]
    let dashboard: Dashboard
    let series: Series?
    @Environment(\.palette) private var palette

    var body: some View {
        let sorted = probes.sorted { order($0) < order($1) }
        let lead = sorted.first.flatMap { dashboard.stats[$0] }
        let leadValue = sorted.first.flatMap(readout)
        let accent = series?.color ?? palette.color("color.section.cpu")
        Card(title: targetName(target), accent: accent) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(ms(leadValue))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.text)
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
        return Readout.value(dashboard.results[p] ?? [], stats: stats, aggregate: aggregate,
                             windowSeconds: Double(SpecResources.defaults.history.recentWindowS))
    }

    private func order(_ p: Probe) -> Int {
        p.protocol == "icmp" ? 0 : p.protocol.hasPrefix("tcp") ? 1 : p.protocol.hasPrefix("udp") ? 2 : 3
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
        let top = GraphBuckets.niceCeiling(max(values.max() ?? 1, 1) * 1.1)
        Chart {
            ForEach(series.points.filter { $0.value != nil }, id: \.start) { p in
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
        .chartXScale(domain: -series.range.seconds...0)
        .chartPlotStyle { $0.clipped() }
        .animation(.linear(duration: refreshSeconds), value: series.now)
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
