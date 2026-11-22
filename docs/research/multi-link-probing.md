# Multi-Link probing

Sources: xnu and mDNSResponder `main` (read 2026-11-22), Apple developer docs, DTS forum posts, Apple Support. No device tests yet; everything below marked "unconfirmed" needs one.

## 1. Pinning a BSD socket to an interface

- DTS: "With BSD Sockets, the best way to bind a socket to an interface is with the `IP_BOUND_IF` (IPv4) or `IPV6_BOUND_IF` (IPv6) socket options." This triggers scoped routing. ([Network Interface Techniques](https://developer.apple.com/forums/thread/734359))
- Both are public, outside `#ifdef PRIVATE` ([in.h](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet/in.h), [in6.h](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet6/in6.h)). `inp_bindif` checks no entitlement ([in_pcb.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet/in_pcb.c)).
- Value: an interface index. Take it from `NWInterface.index` ([docs](https://developer.apple.com/documentation/network/nwinterface/index)), not from a hard-coded name: "Do not hard-code BSD interface names, like `pdp_ip0`. It will end badly." ([DTS](https://developer.apple.com/forums/thread/744044))

| Socket | Option honoured? | Source |
|---|---|---|
| `SOCK_DGRAM`/`IPPROTO_ICMP` | Yes: `icmp_dgram_ctloutput` allows `IP_BOUND_IF`; `rip_output` passes it as `ipoa_boundif` | [ip_icmp.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet/ip_icmp.c), [raw_ip.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet/raw_ip.c) |
| `SOCK_DGRAM`/`IPPROTO_ICMPV6` | Yes: `icmp6_dgram_ctloutput` allows `IPV6_BOUND_IF` | [icmp6.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet6/icmp6.c) |
| UDP, TCP | Yes, through `ip_ctloutput` / `ip6_ctloutput` | [ip_output.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet/ip_output.c), [ip6_output.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet6/ip6_output.c) |

Errors, from the same files:

| When | errno |
|---|---|
| `IP_BOUND_IF` on an AF_INET6 socket, or `IPV6_BOUND_IF` on AF_INET | `EINVAL` |
| Index above the highest or with no interface | `ENXIO` (`inp_bindif`) |
| Index 0, e.g. `if_nametoindex` failed | **Succeeds and unbinds**: "A zero interface scope value indicates an 'unbind'" (`inp_bindif_common`). Guard against it |
| Interface present but no scoped route to the Target | `EHOSTUNREACH` (`ip_output`, `ips_noroute`) |
| No source address on the interface | `ENETUNREACH` (`in_pcbladdr`) |
| NECP policy drop, including denied interface | `EHOSTUNREACH` (`ip_output`, `rip_output`, `udp_output`, `tcp_output`) |

- Bound lookup in `rt_lookup_common` discards an unscoped route on another interface. It then tries a route scoped to the bound interface, and finally the system default route only if it is on that interface. A bound socket never leaks onto another interface through the routing table. ([route.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/route.c))
- Apple warns that what you learn from Darwin source "is not considered API" ([DTS, A Peek Behind the NECP Curtain](https://developer.apple.com/forums/thread/725715)). The errno rows are therefore unconfirmed on iOS 18 devices.

## 2. Cellular while Wi-Fi holds the default route

- "When iOS switches the default route to the Wi-Fi interface, the WWAN interface is still available, it's just not the default route." Also: "an iPhone today might have multiple WWAN interfaces." ([Network Interface Concepts](https://developer.apple.com/forums/thread/734293))
- Dormancy: "we now keep the WWAN interface up where possible" ([DTS, 2021](https://developer.apple.com/forums/thread/675747)). The older archived guide says POSIX sockets do "not automatically activate the device's cellular modem or on-demand VPN" ([Avoiding Common Networking Mistakes, 2017](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/NetworkingOverview/CommonPitfalls/CommonPitfalls.html)). Whether a bound send wakes a dormant context on iOS 18 is unconfirmed.
- NWParameters can force cellular while Wi-Fi is up: DTS showed `requiredInterfaceType = .cellular` plus `prohibitedInterfaceTypes = [.wifi]` giving `interface: pdp_ip0, scoped` ([DTS, 2020](https://developer.apple.com/forums/thread/659034)).

| Setting | Effect on a bound socket | Source |
|---|---|---|
| Settings > Cellular > per-app switch off | NECP enforces it. `CTCellularData.restrictedState == .restricted` means "the app cannot use the cellular network". The kernel returns `EHOSTUNREACH` on an NECP drop. Which errno the switch produces is unconfirmed | [NECP post](https://developer.apple.com/forums/thread/725715), [CTCellularData](https://developer.apple.com/documentation/coretelephony/ctcellulardata), [ip_output.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet/ip_output.c) |
| Cellular Data off globally | No usable cellular context. Expect `ENETUNREACH`/`EHOSTUNREACH` or no `.cellular` interface. Unconfirmed | none |
| Low Data Mode | Not enforced on sockets. The path reports `isConstrained`; "sockets just doesn't have the richness" to apply it | [WWDC19 712](https://developer.apple.com/videos/play/wwdc2019/712/), [isConstrained](https://developer.apple.com/documentation/network/nwpath/isconstrained) |
| Wi-Fi Assist | Replaced by **Connectivity Assist**, in Settings > Wi-Fi, "when Wi-Fi is slow or unusable". It doesn't run while roaming internationally or with cellular Low Data Mode on. Effect on bound sockets undocumented | [Apple Support, 2026-09-14](https://support.apple.com/en-us/102228) |

- `NWPath.UnsatisfiedReason.cellularDenied` exists (iOS 14.2+) but has no documented text ([docs](https://developer.apple.com/documentation/network/nwpath/unsatisfiedreason-swift.enum/cellulardenied)). That a cellular-only `NWPathMonitor` reports it when the switch is off is unconfirmed.
- DTS on monitors in general: "We generally discourage folks from using `NWPathMonitor` ... The only way to tell whether you can talk to someone across the Internet is to try it." ([DTS, 2024](https://developer.apple.com/forums/thread/769550))

## 3. Per-Link Gateway and IP versions

- `NWPathMonitor` has `init()`, `init(requiredInterfaceType:)` and `init(prohibitedInterfaceTypes:)` (iOS 14+). There is **no** `init(requiredInterface:)` ([NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor)). `NWParameters.requiredInterface` exists for connections only ([docs](https://developer.apple.com/documentation/network/nwparameters/requiredinterface)).
- `NWPath.gateways` is "a list of gateways configured on the interfaces available to a path"; `supportsIPv4`/`supportsIPv6`: "whether the path can route" that family ([NWPath](https://developer.apple.com/documentation/network/nwpath)). A monitor per type (`.wifi`, `.cellular`, `.other` for VPN) should give per-Link gateways and IP support. Unconfirmed: whether a `.cellular` monitor stays satisfied while Wi-Fi is default, and what `gateways` holds for a utun.
- With several interfaces of one type, take `availableInterfaces.first` ("in order of preference").
- `.other` covers "virtual networks or networks of unknown types" ([docs](https://developer.apple.com/documentation/network/nwinterface/interfacetype/other)). The app can't tell a VPN from iCloud Private Relay or a Tailscale tunnel by type.

## 4. VPN

| VPN setting | Socket bound to Wi-Fi or cellular | Source |
|---|---|---|
| Default (routes only) | Bypasses the tunnel through scoped routing. Vendors complain apps "bind to a non-UTUN interface and consequently bypass the VPN" | [route.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/route.c), [forum](https://developer.apple.com/forums/thread/109438) |
| `includeAllNetworks` | Still goes through utun: "That can happen if the VPN sets `includeAllNetworks`." Exempt: DHCP, captive portal, companion devices, and `excludeLocalNetworks` traffic (default `true` on iOS) | [DTS](https://developer.apple.com/forums/thread/744044), [includeAllNetworks](https://developer.apple.com/documentation/networkextension/nevpnprotocol/includeallnetworks), [excludeLocalNetworks](https://developer.apple.com/documentation/networkextension/nevpnprotocol/excludelocalnetworks) |
| `enforceRoutes` | Included routes are scoped to the VPN and the setting "supersedes the system routing table and scoping operations by apps". A bound socket to an included route goes through the tunnel | [enforceRoutes](https://developer.apple.com/documentation/networkextension/nevpnprotocol/enforceroutes) |

- NECP can rebind a packet to the tunnel interface after routing: `NECP_KERNEL_POLICY_RESULT_IP_TUNNEL` in `ip_output` sets `ifp = policy_ifp`. So `getsockname` and `IP_BOUND_IF` don't prove where packets leave. ([ip_output.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet/ip_output.c))
- An app can't detect these flags. `NEVPNManager` needs the VPN entitlement and sees only its own configuration.

Does the VPN route this Target?

| Option | Status |
|---|---|
| Routing sysctl / routing socket | Not available: "accessing the routing table has never been supported on iOS" ([DTS 2019](https://developer.apple.com/forums/thread/115109)); "Other Apple platforms don't support routing sockets" ([Network Interface APIs, rev. 2026-09-23](https://developer.apple.com/forums/thread/734338)) |
| Unbound UDP `connect()` + `getsockname()` | Sends nothing. `in_pcbconnect` runs the route lookup and picks the source address ([in_pcb.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/netinet/in_pcb.c)). Match the address to the utun's with `getifaddrs`. DTS documents `getsockname` for a connection's local address ([DTS](https://developer.apple.com/forums/thread/734295)), not this use. Misses NECP rebinds. Unconfirmed |
| UDP `connect()` on a socket bound to the utun | A split tunnel that lacks the route should fail with `EHOSTUNREACH`/`ENETUNREACH`, per `rt_lookup_common`'s scope rules. Inferred from source; unconfirmed |
| UDP `NWConnection` to the Target, read `currentPath` | `availableInterfaces` and `localEndpoint` are documented ([localEndpoint](https://developer.apple.com/documentation/network/nwpath/localendpoint)). Path evaluation includes NECP, so this is likely the most faithful. Unconfirmed |

## 5. `DNSServiceGetAddrInfo` with an interface index

- "If the client passes a positive interface index, then that indicates to do the operation only on that one specified interface." Index 0 sends via unicast "to the appropriate DNS server". ([dns_sd.h](https://github.com/apple-oss-distributions/mDNSResponder/blob/main/mDNSShared/dns_sd.h))
- Resolver choice: "Scoped questions (non-NULL InterfaceID) should consider *only* scoped DNSServers ... and their InterfaceIDs should match" (`DNSServerMatch`). So queries go to that interface's own resolvers, such as the carrier's DNS on cellular, not the default route's. ([mDNS.c](https://github.com/apple-oss-distributions/mDNSResponder/blob/main/mDNSCore/mDNS.c)) Apple builds may use a newer querier path; that it behaves the same is unconfirmed.
- DTS hasn't tried it: "I've never used it to try to force the resolve to work over WWAN." ([DTS 2021](https://developer.apple.com/forums/thread/675747))
- Answers may come from cache (`kDNSServiceFlagAnsweredFromCache` in [dns_sd.h](https://github.com/apple-oss-distributions/mDNSResponder/blob/main/mDNSShared/dns_sd.h)). A cached answer is not a network round trip.

## 6. iCloud Private Relay

- Scope: "all web browsing in Safari, all DNS name resolution queries, and a small subset of traffic from apps. Specifically ... all insecure HTTP traffic, such as TCP port 80." Also: "Private Relay works no matter what networking API you're using." ([WWDC21 10096](https://developer.apple.com/videos/play/wwdc2021/10096/))
- DNS "for all queries sent by the device" goes over Oblivious DoH through the first relay ([Private Relay overview, Dec 2021](https://www.apple.com/privacy/docs/iCloud_Private_Relay_Overview_Dec2021.PDF)). With Private Relay on, the system-DNS Probe likely times ODoH rather than the network's resolver. Unconfirmed for scoped queries.
- ICMP, UDP DNS to an IP literal, and TCP to 443 are outside that scope, so not relayed (inferred). A TCP Probe on port 80 would be relayed.
- VPN traffic and local network traffic skip it ([overview](https://www.apple.com/privacy/docs/iCloud_Private_Relay_Overview_Dec2021.PDF), [WWDC21 10096](https://developer.apple.com/videos/play/wwdc2021/10096/)).
- Apple says it is "different than a VPN" and names no interface. That it shows as a utun is unconfirmed. Probing it as a VPN Link measures nothing the Probes use.

## 7. Data cost per Link

12 Probes in `defaults.json` v5.0.0, plus 1 counted for the Gateway. Request and reply both count; MB is 10⁶ bytes.

| Load | Low (64 B packets, 15-hop trace) | High (100 B, TCP 5 packets, 30-hop trace) |
|---|---|---|
| 13 Probes/s | 13 × 2 × 64 B = 1.7 kB/s → **6.0 MB/h** | 13 × 2 × 100 B + TCP extras 0.7 kB/s = 3.3 kB/s → **11.9 MB/h** |
| Hop Trace, 2 Targets swept every second | 2 × 15 × 2 × 64 B = 3.8 kB/s → **13.8 MB/h** | 2 × 30 × 2 × 100 B = 12 kB/s → **43.2 MB/h** |
| Total | **≈ 20 MB/h** (0.5 GB/day) | **≈ 55 MB/h** (1.3 GB/day) |

Hop Trace dominates. If the full `max_ttl` sweep runs only every `full_sweep_every_s` (30 s) and per-second traces cover only the hops found, the trace term drops toward the low column. Carriers' byte counting (IP vs. radio overhead) is unconfirmed.

## For this app

| Probe | Mechanism per Link |
|---|---|
| ICMP echo, Hop Trace | `IP_BOUND_IF`/`IPV6_BOUND_IF` on the datagram ICMP socket, using `NWInterface.index` from that Link's monitor |
| UDP DNS, TCP connect | Same option, set before `connect`/`sendto` |
| System DNS | `DNSServiceGetAddrInfo` with the Link's interface index; never 0 for a non-default Link |
| Link discovery, Gateway, IP versions | `NWPathMonitor(requiredInterfaceType:)` for `.wifi`, `.cellular`, `.other`. Bind only to an index the monitor currently lists |
| Cellular permission | `CTCellularData.restrictedState`. Show `.restricted` as `denied`; never count it as loss |
| Split-tunnel routing | UDP `NWConnection` to the Target, read `currentPath`; fall back to bound UDP `connect` |
| Errors | `EHOSTUNREACH` is ambiguous (no route or NECP deny). Classify by the monitor's and `CTCellularData` state, not the errno alone. `ENXIO` means the interface vanished: drop the Link |

Must test on a device:

1. All four Probe kinds bound to cellular while Wi-Fi is default: packets leave pdp_ip*, replies return.
2. Per-app cellular switch off: errno per Probe kind, `CTCellularData` state, cellular monitor's `unsatisfiedReason`.
3. Cellular Data off globally, and airplane mode with Wi-Fi on: monitor state and errno.
4. Whether a bound send wakes a dormant cellular context after a long idle.
5. `gateways`, `supportsIPv4`/`IPv6` from each typed monitor, including `.other` for a VPN.
6. Personal VPN in full and split tunnel, plus `includeAllNetworks` and `enforceRoutes`: where en0-bound Probes leave, and which split-tunnel check agrees with reality.
7. `DNSServiceGetAddrInfo` scoped to pdp_ip0 with Wi-Fi default: which resolver answers (compare `whoami`), and with Private Relay on.
8. Private Relay on: does a utun appear, and are ICMP/UDP/TCP-443 Probes unchanged?
9. Measured cellular bytes per hour in Settings > Cellular against the table above.
