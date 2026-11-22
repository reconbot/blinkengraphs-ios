# 14. iOS may differ from the spec, History rules included

**Status:** accepted

iOS measures only while the app is open (ADR 0004). The desktop apps run all day, so the spec's History assumes time is mostly measured. On iOS most of every hour and day is a Pause, which makes this a different tool: a check-up you open when something is wrong, not a monitor. The owner decided iOS may depart from the spec where that difference calls for it, in presentation and in History rules.

- **Each departure is an ADR** naming the spec rule it replaces and the reason. A vector that no longer applies is skipped by name in the test, with a pointer to that ADR.
- **What other platforms compare stays on the spec:** Probe stats, the Verdict, Row fields and their merge. A Verdict or a number on iOS reads the same as on Windows for the same measurements.
- **A departure that would help every platform** still goes to the spec as a PR afterwards.

Candidates found so far (`docs/plan-spec-5.md`):

- The dashboard charts one Link at a time, with a Networks strip and a Compare mode, instead of one line per Target per Link.
- Paused buckets: the spec draws a bucket as Paused once more than half of it is Paused. A short session then vanishes from 7d and All, so iOS may draw any bucket with measured time.
