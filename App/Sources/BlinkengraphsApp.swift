import BlinkengraphsCore
import SwiftUI

@main
struct BlinkengraphsApp: App {
    @State private var monitor = Monitor(defaults: SpecResources.defaults)
    @Environment(\.scenePhase) private var phase
    @AppStorage(Appearance.storageKey) private var appearance = SpecResources.defaults.appearance
    /// `-demo <name>` shows a fixed scenario instead of measuring (screenshots, previews).
    private let demo = Demo.fromLaunchArguments?.dashboard()

    var body: some Scene {
        WindowGroup {
            DashboardView(dashboard: demo ?? monitor.dashboard)
                .preferredColorScheme(appearance.colorScheme)
        }
        // Foreground-only diagnosis: iOS suspends us in the background anyway.
        .onChange(of: phase) { _, phase in
            guard demo == nil else { return }
            if phase == .active { monitor.start() } else { monitor.stop() }
        }
    }
}
