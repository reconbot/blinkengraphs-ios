import BlinkengraphsCore
import SwiftUI
import UIKit

/// `-capture YES`: one launch renders every screenshot the CI publishes and writes them to
/// Documents/shots, then Documents/shots/done. Relaunching per shot and `simctl io screenshot`
/// cost 5–25 s a shot on a hosted runner (docs/research/fast-simulator-screenshots.md); drawing
/// the window in-process takes well under one. The status bar isn't part of the app's window, so
/// it's not in these images.
@MainActor @Observable
final class ScreenshotRun {
    enum Screen {
        case dashboard, settings, targets
        case editor(Defaults.Target)
    }

    struct Shot {
        var name: String
        var demo: Demo
        var dark: Bool
        var bottom: Bool
        var range: GraphRange
        var screen = Screen.dashboard
    }

    static var requested: Bool { UserDefaults.standard.bool(forKey: "capture") }

    /// The order and names the workflow's index expects: scenarios in dark then light, top then
    /// bottom, then the longer ranges, then Settings and its Targets screens in dark then light.
    static let shots: [Shot] = {
        let scenarios: [Demo] = [.ispLoss, .wifi, .cellular, .vpn, .offline, .captive]
        var out: [Shot] = []
        for dark in [true, false] {
            for demo in scenarios {
                for bottom in [false, true] {
                    out.append(Shot(name: "\(demo.rawValue)-\(dark ? "dark" : "light")-\(bottom ? "bottom" : "top")",
                                    demo: demo, dark: dark, bottom: bottom, range: .fifteenMinutes))
                }
            }
        }
        out.append(Shot(name: "range-1h-isp-loss-dark", demo: .ispLoss, dark: true, bottom: false, range: .oneHour))
        out.append(Shot(name: "range-24h-isp-loss-dark", demo: .ispLoss, dark: true, bottom: false, range: .oneDay))
        out.append(Shot(name: "range-7d-wifi-light", demo: .wifi, dark: false, bottom: false, range: .sevenDays))
        // An edited Target with every Probe on, and a new one typed as "gate" so the presets show.
        let screens: [(String, Screen)] = [
            ("settings", .settings), ("targets", .targets),
            ("target-edit", .editor(Defaults.Target(target: "1.1.1.1", icmp: true, dns: true, trace: true, tcp: 443, udp: nil))),
            ("target-new", .editor(Defaults.Target(target: "gate", icmp: true, dns: false, trace: false, tcp: nil, udp: nil))),
        ]
        for dark in [true, false] {
            for (name, screen) in screens {
                out.append(Shot(name: "\(name)-\(dark ? "dark" : "light")", demo: .wifi, dark: dark, bottom: false,
                                range: .fifteenMinutes, screen: screen))
            }
        }
        return out
    }()

    private(set) var dashboard = Demo.wifi.dashboard()
    private(set) var current: Shot?

    func run() async {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("shots", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for shot in Self.shots {
            // The range is read through @AppStorage, and Demo makes Rollups only for a long one.
            UserDefaults.standard.set(shot.range.rawValue, forKey: "range")
            dashboard = shot.demo.dashboard()
            current = shot
            window?.overrideUserInterfaceStyle = shot.dark ? .dark : .light
            // Lay out and draw the new state before capturing it.
            try? await Task.sleep(for: .milliseconds(250))
            if let png = capture() { try? png.write(to: dir.appendingPathComponent("\(shot.name).png")) }
        }
        fm.createFile(atPath: dir.appendingPathComponent("done").path, contents: nil)
    }

    private var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first
    }

    private func capture() -> Data? {
        guard let window else { return nil }
        return UIGraphicsImageRenderer(bounds: window.bounds).pngData { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}

/// The screen a shot shows. Settings screens are drawn as the window's root, not as sheets, so a
/// shot needs no presentation to settle.
struct ShotView: View {
    let run: ScreenshotRun

    var body: some View {
        switch run.current?.screen ?? .dashboard {
        case .dashboard: DashboardView(dashboard: run.dashboard, anchorBottom: run.current?.bottom ?? false)
        case .settings: SettingsView()
        case .targets: NavigationStack { TargetsView() }
        case .editor(let row): TargetEditor(row: row) { _ in }
        }
    }
}
