# 14. Each platform may differ from the spec where its normal use calls for it; iOS does

**Status:** accepted

The spec describes one tool, but the platforms are used differently. Windows and macOS run all day in the tray or menu bar and measure almost continuously. iOS measures only while the app is open (ADR 0004): it is a check-up you open when something is wrong, and most of every hour and day is a Pause. A rule that fits one platform's normal use can misfit another's.

The owner's decision: any platform may depart from the spec where that platform's normal use calls for it, History rules and presentation included. This app applies it to iOS.

- **Each departure is an ADR in the departing platform's repo,** naming the spec rule it replaces and the use that calls for it. A vector that no longer applies is skipped by name in that platform's tests, with a pointer to the ADR.
- **What platforms compare stays on the spec:** Probe stats, the Verdict, Row fields and their merge. The same measurements give the same Verdict and numbers everywhere.
- **A departure that would serve every platform** goes to the spec as a PR afterwards.

iOS departures found so far (`docs/plan-spec-5.md`):

- The dashboard charts one Link at a time, with a Networks strip and a Compare mode, instead of one line per Target per Link.
- Paused buckets: the spec draws a bucket as Paused once more than half of it is Paused. A short session then vanishes from 7d and All, so iOS may draw any bucket with measured time.
