import SwiftUI

@main
struct BlinkengraphsApp: App {
    @State private var monitor = Monitor(defaults: SpecResources.defaults)
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            VerdictView(findings: monitor.verdict, probes: monitor.stats)
                .environment(\.tokens, SpecResources.tokens)
        }
        // Foreground-only diagnosis: iOS suspends us in the background anyway.
        .onChange(of: phase) { _, phase in
            if phase == .active { monitor.start() } else { monitor.stop() }
        }
    }
}
