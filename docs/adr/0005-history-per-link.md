# 5. Probe History is kept per Link

**Status:** accepted, ahead of the spec

`rules/probe-stats.md` keeps one History per Probe. On a phone that hops between Wi-Fi and cellular, that carries one link's loss onto the next: device testing showed "gateway losing 11%" on Wi-Fi, made up of pings sent to the cellular translator before the switch.

The app keeps History per Link (the interface plus its Gateway, `LinkHistories` in Core). The Verdict, the Probe stats and the Hop Traces read only the current Link, and a result belongs to the Link it was sent on. Returning to a Link within the RAM History restores what it had.

- This is a rule the spec lacks, so it goes ahead of the usual order in `docs/sync.md` at the owner's request. The spec carries it as a proposal until it lands in `rules/` with vectors; then this ADR converges on that text.
- No spec vector changes: every vector describes a single Link.
- Without the Access Wi-Fi Information entitlement, two Wi-Fi networks whose Gateways share an address count as one Link. The 15-minute RAM History bounds the overlap.
