# 18. History that crashes launch twice in a row is deleted

**Status:** accepted

3.1.0 crashed on every launch: loading History trapped before it could save anything, so nothing changed between launches (#42). Any future bug in loading, or damaged bytes on disk, could do the same, and the only way out for the user would be deleting the app. History on iPhone is fine to lose; an app that won't open is not.

- **Breaker.** `LoadBreaker` writes a count to `history.loading` before loading starts and removes it once loading, replay and the launch's rewrite have finished. When two launches in a row never finished, the third deletes `history/` and starts with empty History. No copy is kept.
- **Two, not one.** A user can swipe the app away during a load. A single unfinished load must not cost them their History; the price is one extra crash in a real loop.
- **Damaged numbers.** The decoder rejects a Pause or Paused seconds whose value isn't finite, treating it like a torn tail: History turns those times into `Int`, which traps on infinity. The app never writes such values.
- **No format version.** A file this build can't read, from a newer format or damage, ends at the first record it doesn't know, and launch rewrites `archives.bin` without the rest. Since History is fine to lose, partial History is accepted rather than adding a version header.
