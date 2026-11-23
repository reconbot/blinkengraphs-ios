import Testing
import BlinkengraphsCore

// spec rules/probe-group.md, "Normalizing". Replaced by vectors/probe-group once the pin reaches
// the spec release that ships them.
private func t(_ target: String, icmp: Bool = false, tcp: Int? = nil, udp: Int? = nil, dns: Bool = false,
               trace: Bool = false) -> Defaults.Target {
    Defaults.Target(target: target, icmp: icmp, dns: dns, trace: trace, tcp: tcp, udp: udp)
}

@Test func aNormalizedGroupIsUnchanged() {
    let rows = [t("gateway", icmp: true), t("1.1.1.1", icmp: true, tcp: 443, dns: true, trace: true), t("system-dns", dns: true)]
    #expect(Defaults.Target.normalized(rows) == rows)
}

@Test func duplicateRowsMergeIntoTheFirstInItsPlace() {
    #expect(Defaults.Target.normalized([t("gateway", icmp: true), t("1.1.1.1", icmp: true), t("gateway", dns: true)])
        == [t("gateway", icmp: true, dns: true), t("1.1.1.1", icmp: true)])
}

@Test func targetsCompareTrimmedLowercasedAndCanonical() {
    #expect(Defaults.Target.normalized([t(" Example.COM ", icmp: true), t("example.com", trace: true)])
        == [t("example.com", icmp: true, trace: true)])
    #expect(Defaults.Target.normalized([t("2606:4700:4700:0:0:0:0:1111", icmp: true), t("2606:4700:4700::1111", tcp: 443)])
        == [t("2606:4700:4700::1111", icmp: true, tcp: 443)])
}

@Test func portsTakeTheFirstNonNull() {
    #expect(Defaults.Target.normalized([t("example.com", tcp: 443), t("example.com", tcp: 80, udp: 53)])
        == [t("example.com", tcp: 443, udp: 53)])
}

@Test func systemDNSMeasuresDNSOnly() {
    #expect(Defaults.Target.normalized([t("System-DNS", icmp: true, tcp: 443, udp: 53, dns: true, trace: true)])
        == [t("system-dns", dns: true)])
    #expect(Defaults.Target.normalized([t("system-dns", icmp: true)]) == [t("system-dns")])
}
