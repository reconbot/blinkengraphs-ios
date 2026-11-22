import BlinkengraphsCore
import SwiftUI

/// The user's Probe Group, stored as JSON; empty means the spec's (CONTEXT.md "Probe Group").
enum ProbeGroupSetting {
    static let key = "probeGroup"

    static func decode(_ json: String) -> Defaults.ProbeGroup {
        json.isEmpty ? SpecResources.defaults.probeGroup
            : (try? JSONDecoder().decode(Defaults.ProbeGroup.self, from: Data(json.utf8))) ?? SpecResources.defaults.probeGroup
    }

    static func encode(_ group: Defaults.ProbeGroup) -> String {
        group == SpecResources.defaults.probeGroup ? ""
            : (try? JSONEncoder().encode(group)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

/// Settings → Targets: the Probe Group's table, as on Windows. iOS has no UDP Probe, so no UDP column.
struct TargetsView: View {
    @AppStorage(ProbeGroupSetting.key) private var stored = ""
    @Environment(\.palette) private var palette
    @State private var editing: Int?
    @State private var adding = false

    private var group: Defaults.ProbeGroup { ProbeGroupSetting.decode(stored) }

    var body: some View {
        Form {
            Section {
                ForEach(Array(group.targets.enumerated()), id: \.offset) { i, row in
                    Button { editing = i } label: { TargetRowLabel(row: row) }
                        .foregroundStyle(palette.text)
                }
                .onDelete { offsets in update { $0.targets.remove(atOffsets: offsets) } }
                .onMove { from, to in update { $0.targets.move(fromOffsets: from, toOffset: to) } }
                Button("Add Target", systemImage: "plus.circle.fill") { adding = true }
            } footer: {
                Text("An address, a host name, gateway or system-dns. Names are looked up again every 30 seconds.")
            }
            .listRowBackground(palette.card)
            Section("Every") {
                Stepper("Latency \(seconds(group.latencyMs))", value: binding(\.latencyMs), in: 500...10_000, step: 500)
                Stepper("Hop Trace \(seconds(group.traceMs))", value: binding(\.traceMs), in: 500...10_000, step: 500)
            }
            .listRowBackground(palette.card)
            Section {
                Button("Reset to defaults", role: .destructive) { stored = "" }
                    .disabled(stored.isEmpty)
            }
            .listRowBackground(palette.card)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("Targets")
        .toolbar { EditButton() }
        .sheet(item: Binding(get: { editing.map(Edit.init) }, set: { editing = $0?.index })) { edit in
            TargetEditor(row: group.targets[edit.index]) { row in update { $0.targets[edit.index] = row } }
        }
        .sheet(isPresented: $adding) {
            TargetEditor(row: Defaults.Target(target: "", icmp: true, dns: false, trace: false, tcp: nil, udp: nil)) { row in
                update { $0.targets.append(row) }
            }
        }
    }

    private struct Edit: Identifiable { var index: Int; var id: Int { index } }

    private func update(_ change: (inout Defaults.ProbeGroup) -> Void) {
        var g = group
        change(&g)
        stored = ProbeGroupSetting.encode(g)
    }

    private func binding(_ key: WritableKeyPath<Defaults.ProbeGroup, Int>) -> Binding<Int> {
        Binding(get: { group[keyPath: key] }, set: { v in update { $0[keyPath: key] = v } })
    }

    private func seconds(_ ms: Int) -> String {
        ms % 1000 == 0 ? "\(ms / 1000) s" : String(format: "%.1f s", Double(ms) / 1000)
    }
}

private struct TargetRowLabel: View {
    let row: Defaults.Target
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TargetLayout.name(row.target)).lineLimit(1).truncationMode(.middle)
            Text([row.icmp ? "ICMP" : nil, row.tcp.map { "TCP \($0)" }, row.dns ? "DNS" : nil,
                  row.trace && row.traceable ? "Hop Trace" : nil].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "Nothing measured")
                .font(.caption).foregroundStyle(palette.textWeak)
        }
    }
}

private struct TargetEditor: View {
    @State var row: Defaults.Target
    let save: (Defaults.Target) -> Void
    @State private var tcp = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    init(row: Defaults.Target, save: @escaping (Defaults.Target) -> Void) {
        _row = State(initialValue: row)
        _tcp = State(initialValue: row.tcp.map(String.init) ?? "")
        self.save = save
    }

    private var valid: Bool {
        Defaults.Target.isValid(row.target) && (tcp.isEmpty || UInt16(tcp).map { $0 > 0 } == true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("1.1.1.1, example.com, gateway", text: $row.target)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    ForEach(TargetLayout.presets(completing: row.target), id: \.self) { preset in
                        Button { row.target = preset } label: {
                            LabeledContent(TargetLayout.name(preset), value: preset)
                        }
                        .foregroundStyle(palette.text)
                    }
                } header: { Text("Target") } footer: {
                    if !row.target.isEmpty && !Defaults.Target.isValid(row.target) {
                        Text("Not an address or a host name.").foregroundStyle(palette.severity(.crit))
                    }
                }
                Section("Measure") {
                    Toggle("ICMP", isOn: $row.icmp)
                    LabeledContent("TCP port") {
                        TextField("off", text: $tcp).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    Toggle("DNS", isOn: $row.dns)
                    Toggle("Hop Trace", isOn: $row.trace).disabled(!row.traceable)
                }
            }
            .navigationTitle(row.target.isEmpty ? "New Target" : TargetLayout.name(row.target))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var r = row
                        r.target = r.target.trimmingCharacters(in: .whitespaces).lowercased()
                        r.tcp = Int(tcp)
                        if !r.traceable { r.trace = false }
                        save(r)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
        }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
