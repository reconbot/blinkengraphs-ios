# 18. History that crashes launch twice in a row is set aside

**Status:** accepted

3.1.0 crashed on every launch: loading History trapped before it could save anything, so nothing changed between launches (#42). Any future bug in loading, or damaged bytes on disk, could do the same, and the only way out for the user would be deleting the app.

- **Breaker.** `LoadBreaker` writes a count to `history.loading` before loading starts and removes it once loading, replay and the launch's rewrite have finished. When two launches in a row never finished, the third moves `history/` to `history.unreadable/` (replacing any earlier copy) and starts with empty History. Losing the graphs is better than an app that won't open, and the files are kept for diagnosis.
- **Two, not one.** A user can swipe the app away during a load. A single unfinished load must not cost them their History; the price is one extra crash in a real loop.
- **Damaged numbers.** The decoder rejects a Pause or Paused seconds whose value isn't finite, treating it like a torn tail: History turns those times into `Int`, which traps on infinity. The app never writes such values.
- **Not done:** a version header on the files. A file this build can't read still ends at the first record it doesn't know, and launch then rewrites `archives.bin` without the rest.
