# IPv6-only cellular

Device tests on a 5G carrier, 2026-11-22. `NWPath` reported `supportsIPv4 == false`, `supportsIPv6 == true`.

| What | Result |
|---|---|
| Gateway reported by `NWPath.gateways` | `192.0.0.1`: the device's own 464XLAT translator (192.0.0.0/29, [RFC 7335](https://www.rfc-editor.org/rfc/rfc7335)). Pinging it lost about half the replies, so it isn't treated as the Gateway |
| ICMP echo and UDP DNS to `1.1.1.1` and `9.9.9.9` over IPv4 BSD sockets | Worked, 50–70 ms: iOS translates IPv4 socket traffic to IPv6 |
| TCP via `NWConnection` to the IPv4 literal `1.1.1.1:443` | 100% loss. The runner treated `.waiting` as a loss; the cause is unconfirmed. The TCP Probe now uses a BSD socket like the others |
| TTL-limited ICMP (Hop Trace), first hops | No answers. Likely: routers before the carrier's NAT64 are IPv6-only, and their time-exceeded replies can't be translated back to IPv4 (unconfirmed) |

Apple's App Review tests on IPv6-only NAT64 networks, which may lack the device-side 464XLAT translator; IPv4 sockets would then fail. Still to verify before an App Store release.
