# Plan: adopt spec 5.0.0

Issue #31. Spec plan: [`docs/history-redesign.md`, iOS](https://github.com/reconbot/blinkengraphs/blob/v5.0.0/docs/history-redesign.md#ios); decision: spec ADR 0001. Reviewed at `066eb9c`, which pins spec v3.0.0.

## What's in flight

| Item | State |
|---|---|
| #31 Adopt spec 5.0.0 | Open. This plan |
| #29 release 2.1.0 | Open release PR; merges only on the owner's word |
| #24 Adopt spec 2.0.0 | Open, but #25 and #27 shipped it. Close it as completed |
| Spec 4.0.0 | Whole-ms RTTs and per-version Public Address URLs are in. **Not in:** a tie for worst Internet Probe goes to the *first* in Probe Group order; `Verdict.swift:161-162` and ADR 0001 still pick the last |
| Windows, macOS | Implement after iOS (spec plan order). Windows has an open release PR (#39) |

## Domain model

Spec terms only (spec `CONTEXT.md`). What changes in this app's model:

- **A Round is the unit of commit.** Today each Probe result is recorded as it arrives (`Monitor.swift:205-212`). Under `history.md` "Cut Rounds" a Round records all its results or none, decided when its last Probe ends: none if `[start, end]` overlaps a Pause. Results are held per Round and committed together.
- **A Pause is a fact in History, not a gap.** `[begin, end)`, machine-wide, written to Raw. `end` is resume plus a fixed settle time. Three sources: `.background`, launch after a kill (`begin` = newest Raw `at` + 1), first launch.
- **A Link is a measured thing, not the current path.** Today `Measurements.link` is the one current Link. Next: a set of active Links, each with its own Probe Group run, stats, Hop Traces, Raw and Archives. One of them carries the default route and feeds the Verdict.
- **Binding replaces settling, for attribution.** ADR 0013 dropped Rounds across a route change because a result couldn't be tied to its Link. A socket bound to its Link's interface can't land on another one.
- **Stats from now.** Windows and Raw retention count back from the clock, not the newest result (`ProbeStats.swift:59-62`, `Readout.swift:10`, `LinkHistories.swift:45-47`).
- **One source per graph range.** The seam `c`, `HistoryBuckets` and the per-minute line cache go. A closed point never changes.

## Modules

`BlinkengraphsCore` stays Foundation-only, so every vector runs on Linux (ADR 0001). Each module below is a deep one: small interface, the rule hidden inside.

| Module | Interface | Hides | Vectors |
|---|---|---|---|
| `RoundGate` | `records(start:end:pauses:) -> Bool` | Cut-Round rule, settle | `history/rounds` |
| `Raw` | `append(_ record)`, `prune(now:)`, `results(key, from:to:)`, `pauses`, `linkChanges`; `static killPause(newestAt:launch:settle:)` | Retention, record kinds (result, Pause, Link change, hop sweep), the kill Pause | `history/raw` |
| `RawCodec` | `encode([RawRecord]) -> Data`, `decode(Data) -> [RawRecord]` | On-disk format; tolerates a torn tail | own tests |
| `ArchiveWriter` | `advance(now:raw:) -> [WrittenRow]` | A1 from Raw, A2 from A1, A3 from A2, Paused seconds, `g`, retention, the cascade order | `history/rows`, `history/archives` |
| `GraphReader` | `points(range:key:now:aggregate:) -> GraphLine` | Range to source, bucket width, Paused, provisional edge, All's `k` | `history/ranges`, `graph-raw`, `graph-archive`, `graph-all` |
| `ProbeStats` | `stats(results:now:window:raw:)` | Windows from now; empty window has no stats | `probe-stats/*` |
| `Verdict` | gains `sinceSeconds` and the `Paused` domain; tie to first | Resuming rule | `verdict/*` |
| `Measurements` | events in (`commit(round)`, `pauseBegan`, `resumed`, `setLinks`), one `Snapshot` out | Per-Link state, which Link speaks for the Verdict | own tests |

`Row` replaces `Minute` (`Sketch.swift:126`): same fields and merge, new name. `GraphPoint` gains `state` (`value`, `lost`, `paused`) and `provisional`, as the vectors name them.

Deleted: `Rollups`, `RollupFiles`, `RollupHistory`, `HistoryBuckets`, `HistoryLine`, `LinkHistories` (folded into `Raw`), `GraphBuckets.points` and `alignedRange` (`niceCeiling` stays).

App target:

- `RawFile` and `ArchiveFiles` (actors): 12-byte fixed-width Raw records, one file per Link per 10 minutes, flushed every 5 s and at Pause begin; Archives append-only. No `fsync`: written data survives a process kill. Default file protection (until first unlock), since a Pause is often written as the screen locks. ([lifecycle-and-storage](research/lifecycle-and-storage.md))
- `Lifecycle`: start a background task at `.inactive`; at `.background` stop Rounds, append the Pause-begin record, end the task. A suspended app that iOS reclaims runs no code, so the kill Pause is the only record of it. Launch reads the newest record first, measures, and loads the rest off the main actor; then `ArchiveWriter` catches up, then prune.
- `LinkWatcher`: `NWPathMonitor(requiredInterfaceType:)` for `.wifi`, `.cellular` and `.other`, each giving its Link's Gateway, IP versions and `NWInterface.index`; the untyped monitor names the default route.
- Runners bind with `IP_BOUND_IF`/`IPV6_BOUND_IF`, not `NWParameters.requiredInterface`: the Probes are BSD sockets. System DNS passes the interface index to `DNSServiceGetAddrInfo`. `EHOSTUNREACH` on a bound socket is ambiguous, so `denied` comes from monitor and `CTCellularData` state, not the errno. ([multi-link-probing](research/multi-link-probing.md))
- Settings: "Measure cellular while on Wi-Fi", off by default, with the measured data cost.
- Graphs: rebuilt on `GraphReader`. Keep the clock-driven model (one edge time; closed points fixed). Prototype Swift Charts vectorized plots (iOS 18) against a Canvas that reuses closed lines, 6 Targets × 3 Links × 300 points, measured with the Animation Hitches template; record the pick in an ADR. Honour Reduce Motion. No third-party library. ([graph-rendering](research/graph-rendering.md))

## Invariants worth a test

- **Write before prune, cascading.** At launch after a long absence, every A1 Row and Paused second must be written from Raw, A2 from A1, A3 from A2, *before* each source is pruned. Otherwise a 3-day absence loses the steps that ended while the app was dead.
- **A long Pause writes Paused seconds without iterating every step.** A year away is 105 120 A1 steps; fully Paused steps older than A1's retention go straight to the Archive that still keeps them.
- **The clock can go backwards.** If the newest Raw `at` is later than launch, the kill Pause is empty, not negative.
- **Only one writer.** `ArchiveWriter` runs on one actor; a Row is written exactly once even when launch catch-up and the running clock race.

## Spec gaps, decided here

The owner's call: decide each here, build to it, and raise it as a spec PR afterwards. Each decision is low-regret: it either matches a vector or adds a record the spec can drop.

| # | Gap | Decision |
|---|---|---|
| 1 | **VPN loses the Gateway.** The Verdict reads only the default-route Link: under a VPN, the tunnel, which has no Gateway. The `vpn-*` Verdict vectors still feed a `gateway/icmp` Probe. | A tunnel Link's Verdict input takes the Gateway Probes of the Link carrying the tunnel: the active non-tunnel Link that `NWPathMonitor` ranks first. Matches the vectors. |
| 2 | **Network change mid-session.** Pause is machine-wide; nothing covers a new Link appearing. | Not a Pause. A Link that appears, or whose Gateway or IP versions change, waits the settle time before its first Round; other Links keep measuring. A Round on a Link that vanishes mid-Round records nothing. Raw records the Link change. ADR 0013's per-route settle survives, per Link. |
| 3 | **Offline, then killed.** No Probes while Offline, so the kill Pause would swallow the Offline stretch. | Raw records path up and down as Link changes, and each flush that holds nothing else writes a "measuring" mark. The kill Pause begins one second after the newest record of any kind. |
| 4 | **First launch** has no Pause, so "All clear" shows before any stats. | Launch with no Raw is a Pause from launch to launch plus settle. The Verdict reads "Resuming measurements" until stats arrive. |
| 5 | **Archive key collisions.** Two Wi-Fi networks behind `192.168.1.1` share a year of Archives. | Accept it for now: keys stay interface and Gateway, as the spec says. Raise a spec PR for a network discriminator; the IPv6 /64 prefix is the candidate that needs no entitlement. Medium confidence that it is worth the extra key field. |
| 6 | **"Routes its Target"** has no supported API on iOS. | Connect an unbound UDP socket to the Target and read `getsockname`: the source address names the interface the OS chose. Re-checked when the Target or the Links change. Fall back to `NWConnection.currentPath` if the device test disagrees. |
| 7 | **Graph lines per Link** on a phone. | See "Graphs: what's happening", below. |
| 8 | **Cellular data cost** reads 20–55 MB an hour against the spec's 5–10 MB. | Hop Trace runs on cellular too (owner). The opt-in shows the measured cost from the device test, and the app counts and shows the bytes it sent and received per Link. Raise the corrected number in the spec. |
| 9 | **iCloud Private Relay** may route system DNS through the relay. | No decision until the device test. |

## Graphs: what's happening

The user opens the app because something is wrong, and asks three things in order: is it me, which network, and since when. The screen answers them top to bottom.

1. **Verdict, naming its Link.** "Wi-Fi: Gateway OK, 1.1.1.1 losing 12%: ISP problem". It speaks for the default-route Link, as the spec says.
2. **Links strip.** One row per active Link: name, state colour from its own Findings, Gateway and primary Target latency, loss, and bytes spent. The default-route Link is marked. This is where other Links show their state (spec: "in the Panel only"). Tapping a row picks it for the chart.
3. **Latency chart, one Link at a time.** Default: the default-route Link, every Target, so Gateway against internet shows where the fault sits, as it does today. A "Compare Links" toggle switches to the primary Target on every Link, one colour per Link, which answers "is it the Wi-Fi or the carrier". Both modes draw Paused shading, loss marks, the provisional edge and Link-change markers, so every gap explains itself.

This departs from the spec's "one line per Link by default". The reason: six Targets times three Links is 18 lines in 190 pt, and the two questions need different cuts of the same data. Raise it in the spec with the other gaps.

## Pull requests

Each passes CI; feature PRs merge when tests pass.

1. **`feat!: follow spec 5.0.0` (core).** Bump `spec` to v5.0.0. All core modules above, the tie-break fix, every vector passing. The app compiles against the new core with one Link and in-memory Raw. Removes the v3 History code. ADRs: supersede 0005, 0007, 0012, 0013; amend 0001's tie note.
2. **`feat: Raw and Archives on disk; Pauses`.** `RawFile`, `ArchiveFiles`, `Lifecycle`. Delete the old `rollups/` directory on first launch (owner: drop it). ADRs: settle time (from the device test), Raw write cadence and format.
3. **`feat: measure every active Link`.** `LinkWatcher`, bound runners, cellular opt-in setting, per-Link Snapshot.
4. **`feat: graphs per Link, Paused and provisional`.** The Links strip, the chart rebuild with Compare Links, after the rendering prototype.
5. **Spec PRs** for gaps 1–6 and 8 and the graph default, with vectors where a rule changes.

PR 1 is large because the vectors change together; landing it first keeps every later PR green on the spec CI check.

## Device tests

Done on a device, results into `docs/research/`:

- Settle time: first-reply time after `.active` on Wi-Fi, cellular and VPN. Instrument a debug build to log, per Probe, time from `.active` to first reply.
- Raw write cadence: MetricKit `MXDiskIOMetric` over a 1 h session; the model predicts about 6 MB an hour at 5 s.
- Launch time with a full 2 h of Raw.
- Binding, VPN, cellular switch and Private Relay: the nine tests in [multi-link-probing](research/multi-link-probing.md#for-this-app).
- Lifecycle event order for Home, app switcher, lock and a call; the Pause write under lock ([lifecycle-and-storage](research/lifecycle-and-storage.md#for-this-app)).
- Graph frame cost for the prototype on a ProMotion and a 60 Hz iPhone.
- Kill: force-quit and jetsam (Xcode memory warning loop), then relaunch; the gap reads Paused.

## Open questions for the owner

1. The Links strip and the Compare Links toggle above: right shape, or should the chart default to comparing Links?
