# 12. Backgrounding pauses measuring; it is not shutting down

**Status:** superseded by ADR 0015

Measuring stops when the scene goes to `.background` and resumes at `.active` (ADR 0004). `.inactive` (a screenshot, Control Center, a notification) keeps measuring.

The spec says shutting down writes every pending minute (`rules/history.md`, "Minutes"). Doing that on every trip to the background wrote the open minute early. A quick return then split that minute: the written part became one 60 s storage bucket, and the 1m graph showed a loss bar where the line had been. So a pause writes only the minutes that have ended (`Rollups.flushEnded`). If iOS ends the suspended app, at most the open minute is lost.

A Probe still in flight when the app pauses can't observe its reply, so it isn't counted. Its timeout ran out while the process was suspended, and recording it as lost gave a spurious loss and Verdict on return. Results of a round that was cancelled, or that arrived later than its timeout plus the grace `g`, are dropped. A late result would also break the grace that write-once relies on.

The spec doesn't yet cover either case, pausing or unobserved Probes; Windows sleep raises both.
