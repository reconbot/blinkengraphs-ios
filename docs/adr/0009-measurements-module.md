# 9. Measurements: what results mean, in the core; when to measure, in the app

**Status:** accepted

`Monitor` had grown to mix scheduling and sockets with the rules about what results mean: which Link a result belongs to, denied versus lost, resets on a Link change, per-Link Hop Traces and sweep plans, and the order hop results must be recorded in. Those rules caused real bugs (cross-link loss, ADR 0005), and behind real sockets they couldn't be tested.

`BlinkengraphsCore.Measurements` now holds them behind a small interface:

- Events in: `setPath`, `record`, `sweepTTLs`/`recordSweep`, `setCaptivePortal`, `setPublicAddress`. Each takes the Link the work was sent on, so a late answer never lands on the wrong Link.
- One `Snapshot` out: findings, stats, denied, hops, results, captive portal, Public Address.

It runs on Linux and has tests (`MeasurementsTests`). `Monitor` keeps the timers, runners and lookups, and publishes one snapshot per refresh. That is also one observed write per refresh, where it used to be one per Probe result.

Rollups stay outside: their storage is a reference shared with the graphs (ADR 0007), and `record` returns the result for the app to roll up.
