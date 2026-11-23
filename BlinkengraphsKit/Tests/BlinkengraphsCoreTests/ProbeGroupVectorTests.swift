import Foundation
import Testing
import BlinkengraphsCore

private struct File: Decodable {
    struct Case: Decodable { var name: String; var targets: [Defaults.Target]; var expected: [Defaults.Target] }
    var cases: [Case]
}

/// spec rules/probe-group.md, "Normalizing".
@Test func probeGroupNormalizeVectors() throws {
    for (_, file) in try Spec.vectors("probe-group", as: File.self) {
        for c in file.cases {
            #expect(Defaults.Target.normalized(c.targets) == c.expected, "\(c.name)")
        }
    }
}

@Test func theSystemDNSDomainIsTheSpecDefault() throws {
    #expect(try Defaults.decode(Spec.file("defaults.json")).systemDNSDomain == "microsoft.com")
}
