import BlinkengraphsCore
import SwiftUI
import UIKit

@main
struct BlinkengraphsApp: App {
    @State private var monitor = Monitor(defaults: SpecResources.defaults,
                                         group: ProbeGroupSetting.decode(UserDefaults.standard.string(forKey: ProbeGroupSetting.key) ?? ""))
    @AppStorage(ProbeGroupSetting.key) private var probeGroup = ""
    @Environment(\.scenePhase) private var phase
    @AppStorage(Appearance.storageKey) private var appearance = SpecResources.defaults.appearance
    /// `-demo <name>` shows a fixed scenario instead of measuring (screenshots, previews).
    private let demo = Demo.fromLaunchArguments?.dashboard()

    var body: some Scene {
        WindowGroup {
            DashboardView(dashboard: demo ?? monitor.dashboard)
                .onAppear { apply(appearance) }
                .onChange(of: appearance) { _, new in apply(new) }
                .onChange(of: probeGroup) { _, json in monitor.setProbeGroup(ProbeGroupSetting.decode(json)) }
        }
        // Foreground-only diagnosis: iOS suspends us in the background anyway.
        .onChange(of: phase) { _, phase in
            guard demo == nil else { return }
            if phase == .active { monitor.start() } else { monitor.stop() }
        }
    }

    /// Set on the window, not with `preferredColorScheme`: that one didn't reach an open sheet,
    /// and setting it back to nil doesn't return to following the system.
    private func apply(_ appearance: Appearance) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}
