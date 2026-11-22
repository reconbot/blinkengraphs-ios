# 17. Every active Link is measured, each pinned to its interface

**Status:** accepted

Spec 5 measures several Links at once (spec `rules/history.md`, "Links"; `docs/history-redesign.md`). On iOS that is Wi-Fi and cellular, plus a VPN when one carries the default route.

- **Which Links:** the default-route Link, unbound, so it goes wherever the OS sends traffic; then each other working Wi-Fi, wired or cellular Link, pinned to its interface. Cellular while Wi-Fi carries the default route only when the user turns on "Measure cellular while on Wi-Fi" (off by default), since it spends their data plan.
- **How:** `IP_BOUND_IF` and `IPV6_BOUND_IF` on the BSD sockets every Probe uses, not `NWParameters.requiredInterface` as the spec's plan suggested: the Probes aren't Network.framework connections. The system-DNS Probe passes the interface index to `DNSServiceGetAddrInfo`. Neither needs an entitlement (`docs/research/multi-link-probing.md`).
- **Finding Links:** one `NWPathMonitor(requiredInterfaceType:)` per kind gives each Link its interface index, Gateway and IP versions. Each waits out its own settle after it appears or changes, as ADR 0013's does for the default route.
- **Through a VPN:** the tunnel has no Gateway, so its Verdict takes the Gateway Probe of the Link carrying it (decision 1 in `docs/plan-spec-5.md`). A Target the tunnel doesn't route is skipped on it: an unbound UDP `connect` and `getsockname` name the interface the OS would use (decision 6). A VPN that sets `includeAllNetworks` or `enforceRoutes` may still capture the pinned Probes; the app can't see those flags.
- **The Verdict speaks for the default-route Link.** Each other Link gets its own Findings from its own Probes, for the Networks strip.
- **Not yet:** Hop Traces run on the default-route Link only.

Unverified on a device: that pinned Probes leave by cellular while Wi-Fi is the default route, the errno a per-app cellular switch produces, and the data cost the setting quotes. The nine device tests in the research note settle them.
