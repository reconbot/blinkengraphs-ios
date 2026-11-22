# 15. History follows spec 5: Raw, Archives and Pauses

**Status:** accepted. Supersedes 0005, 0007 and 0012; amends 0013.

Spec 5.0.0 replaced Rollups with Raw plus three Archives and made unmeasured time a Pause (spec ADR 0001, `rules/history.md`). The core implements it Foundation-only (ADR 0001) and passes every vector of spec 5.2.0:

- **`History`** keeps Raw, the Pauses and A1, A2 and A3 per key (a Probe on a Link). `advance(now:)` writes each Row once its step has ended, lowest Archive first, then prunes, so a long absence loses nothing an Archive should still hold. Paused seconds are machine-wide and computed from the Pauses, which equals summing the steps below.
- **`Graph`** draws each range from one source, with Paused buckets and a provisional edge.
- **`Measurements`** commits a Round whole or not at all: a Round a Pause cuts records nothing. `.background` begins a Pause; launch and `.active` end one a settle time later. Launch with nothing measured before is a Pause too, so the Verdict reads "Resuming measurements" rather than "All clear".
- **Stats** count back from now; a Probe with an empty window has none.

What it replaces:

- **ADR 0005, History per Link:** now the spec's rule. Archives key a Link by interface and Gateway, as `Link` already does.
- **ADR 0007, Rollups as daily JSON Lines:** gone. The owner chose to drop the old files rather than convert them; the app deletes `rollups/` on launch.
- **ADR 0012, backgrounding is a pause:** now the spec's Pause, with cut Rounds instead of a late-arrival deadline.
- **ADR 0013, path settle:** the settle after a return to the app is the Pause's settle time. The quiet period after a route change stays, per decision 2 in `docs/plan-spec-5.md`.

Interim: History lives in memory until Raw and Archives reach disk (`docs/plan-spec-5.md`, PR 2), so a relaunch starts empty. The settle time is 2 s, the spec vectors' value, until a device test sets it.
