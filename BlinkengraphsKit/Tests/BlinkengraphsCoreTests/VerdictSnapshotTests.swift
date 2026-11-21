import Foundation
import Testing
import BlinkengraphsCore

@Test func snapshotRoundTripsThroughDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "snapshot-test-\(UUID())"))
    let store = VerdictSnapshotStore(defaults: defaults)
    #expect(store.load() == nil)

    let snap = VerdictSnapshot(
        at: Date(timeIntervalSince1970: 1_800_000_000),
        findings: [Finding(domain: .isp, severity: .crit, headline: "Gateway OK, 8.8.8.8 losing 23%: ISP problem")]
    )
    #expect(store.save(snap) == true)
    #expect(store.load() == snap)
}

@Test func saveReportsOnlyFindingChanges() throws {
    // The widget's reload budget is small: reload only when the Findings change.
    let defaults = try #require(UserDefaults(suiteName: "snapshot-test-\(UUID())"))
    let store = VerdictSnapshotStore(defaults: defaults)
    let clear = [Finding(domain: .clear, severity: .ok, headline: "All clear")]
    #expect(store.save(VerdictSnapshot(at: Date(timeIntervalSince1970: 1), findings: clear)) == true)
    #expect(store.save(VerdictSnapshot(at: Date(timeIntervalSince1970: 2), findings: clear)) == false)
    #expect(store.load()?.at == Date(timeIntervalSince1970: 2))
}
