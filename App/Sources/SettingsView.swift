import BlinkengraphsCore
import SwiftUI

extension Appearance {
    /// The key Settings stores the choice under; also settable at launch (`-appearance dark`).
    static let storageKey = "appearance"

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @AppStorage(Appearance.storageKey) private var appearance = SpecResources.defaults.appearance
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(palette.card)
                } header: {
                    Text("Theme")
                } footer: {
                    Text("System follows your iPhone's Light or Dark setting.")
                }
                Section("About") {
                    LabeledContent("App", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                    LabeledContent("Spec", value: SpecResources.specVersion)
                }
                .listRowBackground(palette.card)
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sensoryFeedback(.selection, trigger: appearance)
    }
}
