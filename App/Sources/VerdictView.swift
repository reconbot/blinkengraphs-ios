import BlinkengraphsCore
import SwiftUI

struct VerdictView: View {
    let findings: [Finding]
    let probes: [Probe: ProbeStats]
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
                Section("Probes") {
                    ForEach(probes.keys.sorted { ($0.target, $0.protocol) < ($1.target, $1.protocol) }, id: \.self) { p in
                        let s = probes[p]!
                        LabeledContent("\(p.target) \(p.protocol)") {
                            Text(s.rttMs.map { "\(Int($0.rounded())) ms" } ?? "—")
                            + Text(s.loss > 0 ? "  \(Int((s.loss * 100).rounded()))% loss" : "")
                                .foregroundStyle(tokens.swiftUIColor("color.loss"))
                        }
                        .monospacedDigit()
                    }
                }
            }
            .navigationTitle("blinkengraphs")
        }
    }

    private func icon(_ s: Severity) -> String {
        switch s {
        case .crit: "xmark.octagon.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .ok: "checkmark.circle.fill"
        }
    }
}

#Preview("ISP loss") {
    VerdictView(
        findings: [Finding(domain: .isp, severity: .crit, headline: "Gateway OK, 8.8.8.8 losing 23%: ISP problem")],
        probes: [
            Probe(target: "gateway", protocol: "icmp"): ProbeStats(loss: 0, rttMs: 3, baselineMs: 2, jitterMs: 1),
            Probe(target: "8.8.8.8", protocol: "tcp:443"): ProbeStats(loss: 0.23, rttMs: 95, baselineMs: 19, jitterMs: 14),
        ]
    )
}
