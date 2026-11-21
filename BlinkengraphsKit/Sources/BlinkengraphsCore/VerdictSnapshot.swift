import Foundation

/// The last Verdict, handed from the app to the widget through the App Group.
public struct VerdictSnapshot: Codable, Equatable, Sendable {
    public var at: Date
    public var findings: [Finding]

    public init(at: Date, findings: [Finding]) { self.at = at; self.findings = findings }
}

public struct VerdictSnapshotStore {
    private static let key = "verdict-snapshot"
    private let defaults: UserDefaults

    /// Pass `UserDefaults(suiteName: <App Group>)` so the widget reads what the app wrote.
    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> VerdictSnapshot? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(VerdictSnapshot.self, from: $0) }
    }

    /// Saves `snapshot` and returns whether its Findings differ from the stored ones,
    /// which is when the widget's timeline is worth reloading.
    @discardableResult
    public func save(_ snapshot: VerdictSnapshot) -> Bool {
        let changed = load()?.findings != snapshot.findings
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.key) }
        return changed
    }
}
