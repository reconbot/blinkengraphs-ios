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
}

extension Aggregate {
    static let storageKey = "graphAggregate"
    static let readoutStorageKey = "readoutAggregate"

    var label: String {
        switch self {
        case .p50: "p50"
        case .p95: "p95"
        case .p99: "p99"
        case .avg: "avg"
        case .max: "max"
        }
    }
}

struct SettingsView: View {
    @AppStorage(Appearance.storageKey) private var appearance = SpecResources.defaults.appearance
    @AppStorage(Aggregate.storageKey) private var aggregate = SpecResources.defaults.graphAggregate
    @AppStorage(Aggregate.readoutStorageKey) private var readout = SpecResources.defaults.readoutAggregate
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
                Section {
                    Picker("Graphs show", selection: $aggregate) {
                        ForEach(Aggregate.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(palette.card)
                } header: {
                    Text("Graphs show")
                } footer: {
                    Text("What each point of a graph shows when it covers several samples. p95 shows the slow tail a median hides.")
                }
                Section {
                    Picker("Numbers show", selection: $readout) {
                        ForEach(Aggregate.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(palette.card)
                } header: {
                    Text("Numbers show")
                } footer: {
                    Text("The latency on each Target card, over its last \(SpecResources.defaults.history.recentWindowS) seconds. The Verdict always uses the median.")
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
        .sensoryFeedback(.selection, trigger: aggregate)
        .sensoryFeedback(.selection, trigger: readout)
    }
}
