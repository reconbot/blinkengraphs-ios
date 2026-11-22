import BlinkengraphsCore
import SwiftUI
import UIKit

struct DashboardView: View {
    let dashboard: Dashboard
    /// `-anchor bottom` opens scrolled to the end, so screenshots can reach the Hop Traces.
    var anchorBottom = UserDefaults.standard.string(forKey: "anchor") == "bottom"
    @Environment(\.palette) private var palette
    /// Remembered; also settable at launch (`-range 24h`) for screenshots.
    @AppStorage("range") private var range: GraphRange = .fifteenMinutes
    @State private var showingSettings = false
    @AppStorage(Aggregate.storageKey) private var aggregate = SpecResources.defaults.graphAggregate
    /// The screen as it was when a scroll began. Redrawing every second under a moving finger
    /// made scrolling jitter, so updates wait until the scroll ends.
    @State private var frozen: Dashboard?

    /// `Severity` sorts most severe first.
    private var worst: Severity { dashboard.findings.map(\.severity).min() ?? .ok }

    var body: some View {
        let dashboard = frozen ?? self.dashboard
        // Once per refresh, shared by the chart, its legend and the Target cards.
        let series = Series.all(dashboard, range: range, palette: palette, aggregate: aggregate)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VerdictBanner(findings: dashboard.findings)
                    ConnectionChips(path: dashboard.path)
                    LatencyCard(dashboard: dashboard, series: series, range: $range, animate: frozen == nil)
                    TargetGrid(dashboard: dashboard, series: series)
                    PublicAddressCard(readings: dashboard.publicAddress)
                    ForEach(dashboard.layout.traced.filter { dashboard.hops[$0.target] != nil }) { entry in
                        HopTraceCard(target: entry.target, rows: dashboard.hops[entry.target] ?? [], names: dashboard.hopNames)
                    }
                    Footer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            // `-anchor bottom` opens scrolled to the end, so screenshots can reach the Hop Traces.
            .defaultScrollAnchor(anchorBottom ? .bottom : .top)
            .onScrollPhaseChange { _, phase in
                frozen = phase.isScrolling ? (frozen ?? self.dashboard) : nil
            }
            .background(palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) { Wordmark(severity: worst) }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    reportMenu
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .toolbarBackground(palette.background, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
        .tint(palette.color("color.section.network"))
        .sensoryFeedback(trigger: worst) { old, new in new < old ? .warning : nil }
    }

    private var reportMenu: some View {
        Menu {
            Button("Copy report", systemImage: "doc.on.doc") { UIPasteboard.general.string = report(redact: false) }
            Button("Copy redacted report", systemImage: "eye.slash") { UIPasteboard.general.string = report(redact: true) }
            ShareLink(item: report(redact: false)) { Label("Share report", systemImage: "square.and.arrow.up") }
            // MetricKit hang and crash reports, for diagnosing a freeze (Diagnostics).
            let diagnostics = Diagnostics.saved
            if !diagnostics.isEmpty {
                ShareLink(items: diagnostics) {
                    Label("Share diagnostics (\(diagnostics.count))", systemImage: "stethoscope")
                }
            }
        } label: {
            Label("Report", systemImage: "doc.text.magnifyingglass")
        }
    }

    /// A plain-text snapshot for pasting into a bug report; redacted hides public addresses and names.
    private func report(redact: Bool) -> String {
        let path = dashboard.path
        let info = Bundle.main.infoDictionary
        let app = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let connection = path.facts.map { ($0.label, $0.value) }
        return Report.text(ReportInput(
            generatedAt: .now,
            header: ["app \(app)", "spec \(SpecResources.specVersion)",
                     "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"],
            verdict: dashboard.findings, connection: connection, probes: dashboard.stats, denied: dashboard.denied,
            hops: dashboard.hops, names: dashboard.hopNames, targets: dashboard.layout.targets
        ), redact: redact)
    }
}

// MARK: - Header

/// The name with a status LED that blinks while probes run.
private struct Wordmark: View {
    let severity: Severity
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(palette.severity(severity))
                .frame(width: 9, height: 9)
                .shadow(color: palette.severity(severity), radius: 4)
                .phaseAnimator([1.0, 0.35]) { led, opacity in led.opacity(opacity) } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
            Text("blinkengraphs")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(palette.text)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Verdict

private struct VerdictBanner: View {
    let findings: [Finding]
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lead = findings.min { $0.severity < $1.severity }
        let rest = findings.filter { $0 != lead }
        let tint = palette.severity(lead?.severity ?? .ok)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(lead?.severity ?? .ok))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: lead?.severity == .crit)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lead.map { $0.domain == .clear ? "Verdict" : domainName($0.domain) } ?? "Verdict")
                        .font(.caption.weight(.semibold)).textCase(.uppercase).tracking(0.8)
                        .foregroundStyle(tint)
                    Text(lead?.headline ?? "Measuring…")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(Array(rest.enumerated()), id: \.offset) { _, f in
                Label(f.headline, systemImage: icon(f.severity))
                    .font(.subheadline)
                    .foregroundStyle(palette.severity(f.severity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.card))
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tint.opacity(0.55), lineWidth: 1))
        .shadow(color: tint.opacity(scheme == .dark ? 0.35 : 0.15), radius: 18, y: 4)
        .animation(.smooth, value: lead)
        .accessibilityElement(children: .combine)
    }

    private func domainName(_ d: FaultDomain) -> String {
        switch d {
        case .localLoad: "This device"
        case .lan: "Local network"
        case .isp: "ISP"
        case .dns: "DNS"
        case .remote: "Remote"
        case .icmpFiltering: "ICMP filtered"
        case .selfSaturation: "Upload saturated"
        case .offline: "Offline"
        case .vpn: "VPN"
        case .captivePortal: "Captive portal"
        case .clear: "All clear"
        case .paused: "Paused"
        }
    }
}

func icon(_ s: Severity) -> String {
    switch s {
    case .crit: "xmark.octagon.fill"
    case .warn: "exclamationmark.triangle.fill"
    case .ok: "checkmark.seal.fill"
    }
}

// MARK: - Connection

private struct ConnectionChips: View {
    let path: PathState
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !path.satisfied {
                    chip("No network path", "wifi.slash", tint: palette.severity(.crit))
                } else {
                    ForEach(path.shownInterfaces, id: \.self) { chip($0, symbol($0)) }
                    if path.ipv4 { chip("IPv4", "4.circle") }
                    if path.ipv6 { chip("IPv6", "6.circle") }
                    if let gw = path.gateway { chip(gw, "point.3.connected.trianglepath.dotted") }
                    if let q = path.linkQuality { chip(q, "waveform.path.ecg") }
                    if path.expensive { chip("Metered", "dollarsign.circle") }
                    if path.constrained { chip("Low Data", "tortoise") }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    /// One chip per kind. iOS lists every interface it could use, several cellular ones among them,
    /// and a VPN app's tunnel even when it carries nothing; VPN shows only when traffic goes through it.
    private func symbol(_ interface: String) -> String {
        switch interface {
        case "Wi-Fi": "wifi"
        case let s where s.hasPrefix("Cellular"): "antenna.radiowaves.left.and.right"
        case "Ethernet": "cable.connector"
        case "VPN": "lock.shield"
        default: "network"
        }
    }

    private func chip(_ text: String, _ symbol: String, tint: Color? = nil) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(tint ?? palette.text)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(palette.card))
            .overlay(Capsule().strokeBorder(tint?.opacity(0.6) ?? palette.cardEdge, lineWidth: 1))
    }
}

// MARK: - Public Address

/// spec rules/public-address.md, "Reading the answers".
private struct PublicAddressCard: View {
    let readings: [IPFamily: PublicAddressReading]
    @Environment(\.palette) private var palette

    var body: some View {
        Card(title: "Public Address", accent: palette.color("color.section.upload")) {
            VStack(alignment: .leading, spacing: 10) {
                row("IPv4", readings[.ipv4], family: "IPv4")
                row("IPv6", readings[.ipv6], family: "IPv6")
            }
        }
    }

    private func row(_ label: String, _ r: PublicAddressReading?, family: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(palette.textWeak).frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                switch r?.state {
                case nil:
                    Text("Looking up…").foregroundStyle(palette.textWeak)
                case .none?:
                    Text("No \(family) internet").foregroundStyle(palette.textWeak)
                case .nat64?:
                    Text("IPv6-only network with NAT64").foregroundStyle(palette.text)
                    if let a = r?.address { Text("shared IPv4 \(a)").font(.caption).foregroundStyle(palette.textWeak) }
                case .agree?:
                    address(r?.address, asn: r?.asn)
                case .single?:
                    address(r?.address, asn: r?.asn)
                    Text("one source: \(r?.source == .dns ? "DNS" : "HTTPS") only")
                        .font(.caption).foregroundStyle(palette.textWeak)
                case .differ?:
                    Text("DNS \(r?.dns ?? "")").foregroundStyle(palette.text)
                    Text("HTTPS \(r?.https ?? "")").foregroundStyle(palette.text)
                    Label("DNS and HTTPS leave by different paths", systemImage: "arrow.triangle.branch")
                        .font(.caption).foregroundStyle(palette.severity(.warn))
                }
            }
            .font(.callout)
            .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func address(_ a: String?, asn: String?) -> some View {
        Text(a ?? "").foregroundStyle(palette.text).lineLimit(1).minimumScaleFactor(0.7)
        if let asn { Text("AS\(asn)").font(.caption).foregroundStyle(palette.textWeak) }
    }
}

// MARK: - Shared card chrome

/// A card with the Windows panel's accent tick beside its title.
struct Card<Trailing: View, Content: View>: View {
    let title: String
    var accent: Color
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Capsule().fill(accent).frame(width: 3, height: 14)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                trailing
            }
            content
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.cardEdge, lineWidth: 1))
    }
}

extension Card where Trailing == EmptyView {
    init(title: String, accent: Color, @ViewBuilder content: () -> Content) {
        self.init(title: title, accent: accent, trailing: { EmptyView() }, content: content)
    }
}

private struct Footer: View {
    @Environment(\.palette) private var palette

    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Text("app \(version) · spec \(SpecResources.specVersion)")
            .font(.caption2).monospacedDigit()
            .foregroundStyle(palette.textWeak)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }
}


/// spec rules/probe-stats.md: displays show whole milliseconds.
func ms(_ v: Double?) -> String { v.map(RTT.display) ?? "—" }

func percent(_ loss: Double) -> String { "\(Int((loss * 100).rounded()))%" }

#Preview("ISP loss") { DashboardView(dashboard: Demo.ispLoss.dashboard()) }
#Preview("Wi-Fi") { DashboardView(dashboard: Demo.wifi.dashboard()) }
#Preview("5G IPv6-only") { DashboardView(dashboard: Demo.cellular.dashboard()) }
#Preview("VPN") { DashboardView(dashboard: Demo.vpn.dashboard()) }
#Preview("Offline") { DashboardView(dashboard: Demo.offline.dashboard()) }
