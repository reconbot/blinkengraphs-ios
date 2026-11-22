import BlinkengraphsCore
import SwiftUI

struct VerdictView: View {
    let findings: [Finding]
    let probes: [Probe: ProbeStats]
    let denied: Set<Probe>
    let path: PathState
    let hops: [String: [HopRow]]
    @Environment(\.tokens) private var tokens

    var body: some View {
        NavigationStack {
            List {
                Section("Verdict") {
                    ForEach(Array(findings.enumerated()), id: \.offset) { _, f in
                        Label(f.headline, systemImage: icon(f.severity))
                            .foregroundStyle(tokens.severity(f.severity))
                    }
                }
                Section("Connection") {
                    LabeledContent("Path", value: path.satisfied ? "Up" : "Down")
                    LabeledContent("Via", value: [path.interfaces.first, path.radio].compactMap { $0 }
                        .joined(separator: " · ").nonEmpty ?? "—")
                    LabeledContent("Supports", value: [path.ipv4 ? "IPv4" : nil, path.ipv6 ? "IPv6" : nil,
                                                       path.dns ? "DNS" : nil].compactMap { $0 }
                        .joined(separator: ", ").nonEmpty ?? "—")
                    if let quality = path.linkQuality {
                        LabeledContent("Link quality", value: quality)
                    }
                    LabeledContent("Gateway", value: path.gateway ?? "—")
                    if path.expensive || path.constrained {
                        LabeledContent("Limits", value: [path.expensive ? "Expensive" : nil,
                                                         path.constrained ? "Low Data Mode" : nil]
                            .compactMap { $0 }.joined(separator: ", "))
                    }
                }
                Section("Probes") {
                    ForEach(sorted(Set(probes.keys).union(denied)), id: \.self) { p in
                        LabeledContent("\(p.target) \(p.protocol)") { probeValue(p) }
                            .monospacedDigit()
                    }
                }
                ForEach(hops.keys.sorted(), id: \.self) { target in
                    Section("Hop Trace to \(target)") {
                        ForEach(hops[target] ?? [], id: \.ttl) { HopRowView(row: $0) }
                    }
                }
            }
            .navigationTitle("blinkengraphs")
        }
    }

    @ViewBuilder private func probeValue(_ p: Probe) -> some View {
        if denied.contains(p) {
            // Not a loss: the OS refused to send it (rules/probe-stats.md).
            Text("Local Network access denied").foregroundStyle(.secondary)
        } else if let s = probes[p] {
            Text(s.rttMs.map { "\(Int($0.rounded())) ms" } ?? "—")
                + Text(s.loss > 0 ? "  \(Int((s.loss * 100).rounded()))% loss" : "")
                .foregroundStyle(tokens.swiftUIColor("color.loss"))
        }
    }

    private func sorted(_ probes: Set<Probe>) -> [Probe] {
        probes.sorted { ($0.target, $0.protocol) < ($1.target, $1.protocol) }
    }

    private func icon(_ s: Severity) -> String {
        switch s {
        case .crit: "xmark.octagon.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .ok: "checkmark.circle.fill"
        }
    }
}

private struct HopRowView: View {
    let row: HopRow
    @Environment(\.tokens) private var tokens

    var body: some View {
        HStack {
            Text("\(row.ttl)").frame(width: 24, alignment: .trailing).foregroundStyle(.secondary)
            Text(row.addr ?? "*").lineLimit(1)
            Spacer()
            if row.loss > 0 {
                Text("\(Int((row.loss * 100).rounded()))%").foregroundStyle(tokens.swiftUIColor("color.loss"))
            }
            Text(row.avgMs.map { "\(Int($0.rounded())) ms" } ?? "—").frame(width: 60, alignment: .trailing)
        }
        .font(.callout)
        .monospacedDigit()
    }
}

#Preview("ISP loss") {
    var path = PathState()
    path.satisfied = true
    path.interfaces = ["Wi-Fi"]
    path.gateway = "192.168.1.1"
    return VerdictView(
        findings: [Finding(domain: .isp, severity: .crit, headline: "Gateway OK, 8.8.8.8 losing 23%: ISP problem")],
        probes: [
            Probe(target: "8.8.8.8", protocol: "tcp:443"): ProbeStats(loss: 0.23, rttMs: 95, baselineMs: 19, jitterMs: 14),
        ],
        denied: [Probe(target: "gateway", protocol: "icmp")],
        path: path,
        hops: ["1.1.1.1": [
            HopRow(ttl: 1, addr: "192.168.1.1", sent: 10, loss: 0, lastMs: 2, bestMs: 1, avgMs: 2, worstMs: 3),
            HopRow(ttl: 2, addr: nil, sent: 10, loss: 1, lastMs: nil, bestMs: nil, avgMs: nil, worstMs: nil),
            HopRow(ttl: 3, addr: "1.1.1.1", sent: 10, loss: 0.2, lastMs: 14, bestMs: 11, avgMs: 13, worstMs: 20),
        ]]
    )
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
