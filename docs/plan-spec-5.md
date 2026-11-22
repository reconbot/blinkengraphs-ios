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

## Spec gaps found

Each needs a spec PR or an answer before the code that depends on it. Confidence that each is a real gap: high unless marked.

1. **VPN loses the Gateway in the Verdict.** The Verdict reads only the default-route Link. Under a VPN that is the tunnel, which has no Gateway; the Gateway Probe runs on the Wi-Fi Link underneath. Yet `verdict/vpn-isp-loss`, `vpn-icmp-filtered` and `vpn-ipv6-broken` all feed a `gateway/icmp` Probe with `via_vpn`. So either the VPN Link's Verdict borrows the Gateway Probe of the Link it rides on, or rules 1 and 2 never fire under a VPN. Whether today's app gets a Gateway from `NWPath.gateways` while a VPN is preferred is unconfirmed.
2. **Route change inside a session.** Pause covers "not measuring". When Wi-Fi drops and cellular takes over, is there a settle before the new default-route Link is measured? A Pause is machine-wide, so it would also blank every other Link. ADR 0013's per-route settle has no spec home.
3. **Offline then killed.** While the path is down no Probe is sent, so Raw gets nothing. If iOS then kills the app, the Offline stretch becomes part of the kill Pause. Fix candidates: Raw records path-down as a Link change, and "newest `at`" counts every record kind. Medium confidence that this matters to users.
4. **First launch.** "Not yet started" is a Pause in `CONTEXT.md`, but with no Raw there is no `newest_at`, so no Pause and no `since_pause_s`. The Verdict then reads "All clear" with no Probes for the first seconds.
5. **Archive key collisions.** Archives key a Link by interface and Gateway and keep A3 for a year. Home and office Wi-Fi at `192.168.1.1` on `en0` share one history. iOS can't tell them apart without the Access Wi-Fi Information entitlement (ADR 0003). ADR 0005 bounded this by 15 minutes of RAM; now it's permanent.
6. **"Routes its Target"** can't be read on iOS: routing sockets are macOS-only. The candidates (a UDP `NWConnection`'s `currentPath`, or `getsockname` after `connect`) are unconfirmed. A VPN with `includeAllNetworks` or `enforceRoutes` also stops Wi-Fi-bound Probes from bypassing it, and the app can't see those flags.
7. **Graph lines per Link.** Six Targets on three Links is 18 lines on a 190 pt chart. The spec says one line per Link by default; on a phone that may need a different default (one Link, with others on demand).
8. **Cellular data cost.** The spec says 5–10 MB an hour. Counting packets for the default Probe Group gives about 20–55 MB an hour per Link, most of it Hop Trace sweeps. The opt-in text needs the real number, and cellular may need Hop Trace off or slower. Medium confidence: arithmetic, not a device reading.
9. **iCloud Private Relay** relays all system DNS, so the `system-dns` Probe would measure the relay, and its utun may be read as a VPN Link. Unconfirmed on a device.

## Pull requests

Each passes CI; feature PRs merge when tests pass.

1. **`feat!: follow spec 5.0.0` (core).** Bump `spec` to v5.0.0. All core modules above, the tie-break fix, every vector passing. The app compiles against the new core with one Link and in-memory Raw. Removes the v3 History code. ADRs: supersede 0005, 0007, 0012, 0013; amend 0001's tie note.
2. **`feat: Raw and Archives on disk; Pauses`.** `RawFile`, `ArchiveFiles`, `Lifecycle`. Migrate or drop the old `rollups/` (open question). ADRs: settle time (from the device test), Raw write cadence and format.
3. **`feat: measure every active Link`.** `LinkWatcher`, bound runners, cellular opt-in setting, per-Link Snapshot.
4. **`feat: graphs per Link, Paused and provisional`.** The graph rebuild and Link picker.

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

1. Old `rollups/` (up to 7 days of Minutes): convert to A1 Rows (5 Minutes merge exactly into one), or drop?
2. Spec gaps 1–5 and 8: spec PRs first, or decide here and raise them after?
3. Graph default: every Link's lines, or the default-route Link with others on demand?
4. Cellular opt-in: also measure Hop Trace on cellular, or Probes only?
