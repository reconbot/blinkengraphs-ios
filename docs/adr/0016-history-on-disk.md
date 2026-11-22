# 16. History on disk: append-only records, saved every 5 s and when a Pause begins

**Status:** accepted

Spec `rules/history.md` requires Raw on disk at most 10 s after each result and when a Pause begins; on the next launch the unwritten stretch is a Pause. iOS ends a suspended app without running its code, so the last save is the only record of when measuring stopped (`docs/research/lifecycle-and-storage.md`).

- **One record format, in the core.** `History` journals each change as a `HistoryRecord`: result, Pause, mark, route change, Row, Paused seconds, written step. `HistoryCodec` writes them as tagged binary, little-endian; a result is 9 bytes once its key is defined in the file. Replaying a file's records restores the History, and a record cut short by a kill ends the file without losing what came before. The core stays Foundation-only, so all of it runs in `swift test`.
- **Two kinds of file.** Raw records (results, marks, route changes) go to one file per 10 minutes, deleted once Raw and A1 are done with them. Archive records, Pauses included, go to `archives.bin`, kept as long as the Archives. A Pause lives there because A2 and A3 still need it after Raw has dropped it.
- **Saved every 5 s, and at `.background`** inside a background task, with a mark at the moment the Pause begins. While nothing else is recorded, as when Offline, each save writes a mark, so a kill's Pause begins at the last mark, not the last result (decision 3 in `docs/plan-spec-5.md`).
- **No fsync, no atomic append.** Data handed to the kernel survives a killed process; power loss can lose the last seconds, which then read as a Pause.
- **Launch:** load, replay, write the steps that ended while the app was away, then rewrite `archives.bin` to what retention keeps and delete spent Raw files. Writing before pruning keeps a long absence from losing Rows.
- **No database.** The data is append-only and pruned by age; SQLite would add a dependency the Linux tests can't share.

The write volume is estimated at about 6 MB an hour at 5 s (research note, medium confidence). MetricKit's `MXDiskIOMetric` on a device is the check; until then 5 s is a choice, not a measurement.
