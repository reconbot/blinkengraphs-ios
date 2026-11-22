# 7. Rollups on disk as one JSON Lines file per day

**Status:** accepted

The 1h, 24h and 7d graphs read Rollups: one `Minute` (spec `rules/graph-aggregate.md`, "Per-minute storage") per Probe per Link per minute, kept `rollup_days`. `RollupFiles` stores them in Application Support as `rollups/<days since 1970>.jsonl`, one `StoredMinute` per line, with the sketch in the spec's byte encoding, base64.

- **No database.** The data is append-only and read once at launch, so a file per day suffices. Pruning deletes whole days. A line cut short by a crash is skipped.
- **A minute is written once, when it closes.** Writing open minutes on suspend would count their samples twice once the minute closed. A minute still open when iOS kills the app is lost, at most one per Probe.
- **Per Link**, like the RAM History (ADR 0005): the graphs show the current Link's history.
- **Gaps are honest.** The app measures only in the foreground (ADR 0004), so the longer graphs have gaps for the hours it was closed.
