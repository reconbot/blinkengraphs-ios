# 14. Where iOS departs from the spec

**Status:** accepted

Spec [ADR 0002](https://github.com/reconbot/blinkengraphs/blob/main/docs/adr/0002-platforms-may-depart-for-their-normal-use.md) lets a platform depart from a rule where its normal use calls for it. iOS measures only while the app is open (ADR 0004): a check-up opened when something is wrong, with most of every hour and day a Pause. This ADR lists the departures that follow; each entry names the spec rule it replaces and the vectors skipped. Probe stats, the Verdict, and Row fields and their merge stay on the spec.

| Departure | Spec rule replaced | Vectors skipped | State |
|---|---|---|---|
| The dashboard charts one Link at a time, with a Networks strip and Compare networks | `history.md` Graph ranges: one line per Link by default | none | proposed; mock reviewed |
| A bucket with any measured time draws its data; only a wholly Paused bucket draws as Paused | `history.md` Graph ranges: Paused when Paused seconds exceed `w / 2` | to list when built | candidate; owner to decide |

A departure moves to "accepted" when the owner agrees and its code lands. Details: `docs/plan-spec-5.md`.
