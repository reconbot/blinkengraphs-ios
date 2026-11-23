# 8. The system DNS Probe asks the OS resolver for a fresh random name

**Status:** superseded by [spec ADR 0004](https://github.com/reconbot/blinkengraphs/blob/main/docs/adr/0004-system-dns-asks-a-random-name-under-microsoft-com.md), which makes this every platform's rule, under `system_dns_domain` (`microsoft.com`) instead of `dns_query_name`.

The spec's `system-dns` Target measures the DNS server the device is configured with. iOS has no public API that returns that server's address, so this app can't send it a query directly the way it does 1.1.1.1.

`SystemDNSProbeRunner` instead resolves `<12 random characters>.<dns_query_name>` through the OS resolver with `DNSServiceGetAddrInfo`:

- **A fresh name every time,** so neither mDNSResponder's cache nor the server's can answer. The server must reply itself, and with an upstream lookup.
- **NXDOMAIN is a reply.** `kDNSServiceFlagsReturnIntermediates` is set because without it a negative answer produces no callback.
- **No reply before the Probe's timeout is a loss.**

The measured latency includes the server's own lookup, so it reads higher than a cached answer would. That is the delay an app sees on a first visit to a site, which is what "Your DNS server is slow" is about. Confidence: moderate. It has not yet been compared with a direct query to the same server.
