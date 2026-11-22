import SwiftUI
import UIKit

/// `-capture YES`: one launch renders every screenshot the CI publishes and writes them to
/// Documents/shots, then Documents/shots/done. Relaunching per shot and `simctl io screenshot`
/// cost 5–25 s a shot on a hosted runner (docs/research/fast-simulator-screenshots.md); drawing
/// the window in-process takes well under one. The status bar isn't part of the app's window, so
/// it's not in these images.
@MainActor @Observable
final class ScreenshotRun {
    struct Shot {
        var name: String
        var demo: Demo
        var dark: Bool
        var bottom: Bool
        var range: GraphRange
    }

    static var requested: Bool { UserDefaults.standard.bool(forKey: "capture") }

    /// The order and names the workflow's index expects: scenarios in dark then light, top then
    /// bottom, then the longer ranges.
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
