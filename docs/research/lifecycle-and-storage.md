# Lifecycle and storage for Raw and Archives

Sources: Apple documentation and DTS forum posts linked inline, read 2026-11-22. Apple marks most timing values as subject to change; none here is a contract. Lines marked *unconfirmed* have no primary source or come from one older than iOS 18.

## Backgrounding and suspension

- UIKit order when leaving the foreground: will-resign-active, then did-enter-background, then the snapshot, then "the app may be suspended" ([About the background execution sequence](https://developer.apple.com/documentation/uikit/about-the-background-execution-sequence)). With scenes, UIKit calls `sceneDidEnterBackground(_:)` instead of `applicationDidEnterBackground(_:)` and also posts `didEnterBackgroundNotification` from `UIApplication` and `UIScene` ([sceneDidEnterBackground](https://developer.apple.com/documentation/uikit/uiscenedelegate/scenedidenterbackground(_:))).
- SwiftUI `scenePhase` read in the `App` is the aggregate of all scenes. Apple's own example does cleanup in `onChange` when it becomes `.background`, and says "expect the app to terminate soon after" ([ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase), [ScenePhase.background](https://developer.apple.com/documentation/swiftui/scenephase/background)). `.inactive` is sometimes passed through on the way to `.background` ([ScenePhase.inactive](https://developer.apple.com/documentation/swiftui/scenephase/inactive)).
- Exactly when SwiftUI's `.background` is delivered relative to `sceneDidEnterBackground` and the notification isn't documented. *Unconfirmed*; log all three on a device.
- Without a background task, the app gets about 5 s: `applicationDidEnterBackground` "has five seconds to perform any tasks and return. Shortly after that method returns, the system puts your app into the suspended state" ([Extending your app's background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)).
- With `beginBackgroundTask`: "On current systems you can expect about 30 seconds" (Quinn, DTS, [UIApplication Background Task Notes](https://developer.apple.com/forums/thread/85066), last revised 2023-06-16). Apple documents no number; `backgroundTimeRemaining` is "an estimate", not to be used in app logic (same post, [backgroundTimeRemaining](https://developer.apple.com/documentation/uikit/uiapplication/backgroundtimeremaining)).

### `beginBackgroundTask` contract

From [beginBackgroundTask(withName:expirationHandler:)](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(withname:expirationhandler:)) unless noted:

- Its example use is the one this app has: "call this method before writing data to a file to prevent the system from suspending your app while the operation is in progress."
- Call it early, "preferably before your app actually enters the background". The assertion is granted asynchronously; called just before suspension, the app may be suspended first, and if it can't be granted the expiration handler runs.
- Returns `.invalid` if background running isn't possible. Every call must be matched by `endBackgroundTask(_:)`; if not, before time expires "the system kills the app".
- "This method can be safely called on a non-main thread." The expiry handler "is always called on the main thread", must finish "in less than a second or so", and must end the task ([Quinn](https://developer.apple.com/forums/thread/85066)).
- A task begun in the foreground stays dormant: "The background time 'clock' only starts to tick when the background task becomes effective" ([Quinn](https://developer.apple.com/forums/thread/85066)). So beginning one at `.inactive` and ending it on return to `.active` costs nothing.
- A leaked task ends in a watchdog kill (`0x8badf00d`); about 1000 open assertions crash with `0xbada5e47` ([Quinn](https://developer.apple.com/forums/thread/85066)). MetricKit counts timeouts as `cumulativeBackgroundTaskAssertionTimeoutExitCount` ([MXBackgroundExitData](https://developer.apple.com/documentation/metrickit/mxbackgroundexitdata)).
- WWDC25 names this API for "cleaning up file handles or closing database connections" ([Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227/), 10:51).
- `ProcessInfo.performExpiringActivity(withReason:using:)` runs a synchronous block on a concurrent queue and calls it again with `expired == true` if the process is about to be suspended ([docs](https://developer.apple.com/documentation/foundation/processinfo/performexpiringactivity(withreason:using:))). Apple points app extensions to it ([Extending…](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)); in an app, `UIApplication` is the documented path, and the blocking block fits `async` code badly.
- From SwiftUI: `UIApplication.shared` is reachable in a SwiftUI `App` (this app already uses it in `BlinkengraphsApp.apply`), and `onChange` runs on the main actor, so calling it there is legal. Whether the Swift 6 SDK marks the method `nonisolated` is *unconfirmed*; calling it from the main actor avoids the question.

## Termination

- A suspended app that iOS reclaims runs no code. `applicationWillTerminate(_:)` "is generally not called when the user quits the app because the app simply moves to the background", and may be called only when the app "is running in the background (not suspended)" ([applicationWillTerminate](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationwillterminate(_:))).
- Ways a process ends: removed from the multitasking UI, `exit`, suspended and later "terminating the app if it needs to recover memory", a fatal signal, a hard restart (Quinn, [thread 97582](https://developer.apple.com/forums/thread/97582), 2018). He notes `applicationWillTerminate` was called for a swipe-away *while in the foreground*, "last I checked"; *unconfirmed* on iOS 18.
- Memory-pressure terminations are normal and "you cannot fully eliminate them" ([Reducing terminations in your app](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app)). Kills also come from Task Timeout, watchdog, crashes and power loss, none of which run app code.
- So the only record that survives every case is what reached the file system before the kill. On launch, the newest Raw `at` is the last evidence of measuring; the spec's "gap after the last write is a Pause" is the right inference.

## Data protection

- Default class for app files is Complete Until First User Authentication: "If you do not specify a protection level when creating a file, iOS applies the default" ([Encrypting Your App's Files](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files)); "the default class for all third-party app data not otherwise assigned" ([Platform Security: Data Protection classes](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web)). Nothing documents a different default for Application Support.
- Complete: "Shortly after the user locks a device (10 seconds, if the Require Password setting is Immediately), the decrypted class key is discarded" ([Platform Security](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web)); files then can't be read or written ([FileProtectionType.complete](https://developer.apple.com/documentation/foundation/fileprotectiontype/complete)).
- Locking the screen is a common way into `.background`, so the Pause write races the 10 s key discard under Complete. Apple suggests Complete for foreground-only files plus closing them in `applicationProtectedDataWillBecomeUnavailable`, and a weaker class for files written in the background ([Encrypting Your App's Files](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files)).
- Complete Unless Open keeps an already-open file writable after lock, and new files can be created while locked (same page).
- Recommendation: keep the default, Complete Until First User Authentication. Raw holds latencies, Gateways and Access Points (network location hints), not user content. If stronger protection is wanted, Complete Unless Open with the Raw handle kept open across the Pause write.

## Durability of small appends

- `write(2)` puts data in the unified buffer cache (UBC). Quinn: "once the unified buffer cache (UBC) has accepted data for a file, that data will eventually make it to disk", unless there's "a kernel panic or a hardware error". Kevin Elliott (DTS) confirms this holds across process death, "assuming the I/O reached the UBC and ignoring kernel panics" ([thread 763058](https://developer.apple.com/forums/thread/763058), Sep 2024).
- So a process kill (jetsam, swipe, crash, watchdog) loses only what is still in the app's own buffers. `FileHandle.write(contentsOf:)` with nothing buffered in Swift is enough; no `fsync` is needed for this.
- Power loss is different: "the system going down due to full power loss is NOT unusual on iOS", and data can stay unwritten for "seconds" or longer (Kevin Elliott, same thread). `fsync` moves data to the drive but "doesn't however guarantee that the data will be written to permanent storage immediately" nor ordering; `F_FULLFSYNC` flushes the whole drive cache and is "expensive"; `F_BARRIERFSYNC` is the cheap way to get ordering ([WWDC19 Optimizing Storage in Your App](https://developer.apple.com/videos/play/wwdc2019/419/)). `F_FULLFSYNC` "represents a best-effort guarantee … data can still be lost in the case of sudden power loss" ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)); see also [fsync(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html).
- Apple: avoid `fsync` and `F_FULLFSYNC`; "Most apps can use … `F_BARRIERFSYNC`" ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)).
- Atomic writes cost a temp file, unlink and rename, and the atomic `NSDictionary` write "ends with an fsync" ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes), [WWDC19](https://developer.apple.com/videos/play/wwdc2019/419/)). `Data.write(options: .atomic)` replaces a whole file: right for a small file written rarely, wrong for appends.
- A torn tail after power loss or a short write is possible; the reader must skip a partial last record (as `RollupFiles.load` already does for lines).

## Write volume and wear

- Physical writes go in blocks, "frequently 4 KB … saving a file with only a single-byte change writes 4 KB"; creating or deleting a file writes 8 KB of metadata, a rename up to 16 KB ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)). "Modifying an existing file is 8K" ([WWDC19](https://developer.apple.com/videos/play/wwdc2019/419/)).
- Apple's advice: batch small writes, avoid rewriting serialized files, avoid rapid file creation and deletion, avoid explicit syncs ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)); "aggregate changes into a single write", "Batch changes whenever possible to avoid writing small changes at frequent intervals" ([Energy Efficiency Guide for iOS Apps: Minimize I/O](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/MinimizeIO.html), 2016, archived).
- Measuring: `MXDiskIOMetric.cumulativeLogicalWrites`, "the total amount of data written to disk" ([docs](https://developer.apple.com/documentation/metrickit/mxdiskiometric/cumulativelogicalwrites)); Xcode Organizer Disk Writes; Instruments File Activity; `XCTStorageMetric` in a test ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)).
- Threshold: the system reports an exception when writes "exceed a certain threshold in a 24-hour period" ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes), no number). WWDC20 gives it: "when disk writes exceed one gigabyte in a 24-hour period" ([WWDC20 10076](https://developer.apple.com/videos/play/wwdc2020/10076/)). A report is a diagnostic, not necessarily a kill: check "Action Taken"; a "general" 1 GB/day kill limit "is completely unworkable", and the logged "file backed memory dirtied" limit concerns `mmap` I/O (Kevin Elliott, [thread 712491](https://developer.apple.com/forums/thread/712491), 2022).

### Estimate for a 1-hour session

Model, an upper bound: each flush becomes its own physical write of the touched 4 KiB blocks plus 4 KiB of metadata (8 KiB for a small append, matching WWDC19). The kernel may coalesce flushes further, since without `fsync` it decides when to write back.

| Rate | Record | Logical/h | Flush 1 s | Flush 5 s | Flush 10 s |
|---|---|---|---|---|---|
| 13/s (1 Link) | 12 B binary | 0.56 MB | 29.5 MB | 5.9 MB | 2.9 MB |
| 13/s | 40 B JSON | 1.9 MB | 29.5 MB | 5.9 MB | 4.4 MB |
| 40/s (3 Links) | 12 B binary | 1.7 MB | 29.5 MB | 5.9 MB | 4.4 MB |
| 40/s | 40 B JSON | 5.8 MB | 29.5 MB | 8.8 MB | 7.4 MB |

Flush frequency, not record size, dominates below about 4 KiB per flush. Even 1 s flushes stay under 1 GB/day unless the app is in the foreground about 34 h a day.

## Storage choice

| | Segmented append-only files | SQLite (WAL) | SwiftData / Core Data |
|---|---|---|---|
| Survives process kill | Yes, once `write` returns (UBC) | "Transactions are durable across application crashes regardless of the synchronous setting or journal mode" ([sqlite.org pragma](https://www.sqlite.org/pragma.html#pragma_synchronous)) | Built on SQLite ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)) |
| Power loss | Tail may be torn; reader skips it | WAL + `synchronous=NORMAL`: consistent, last commits may roll back (same page) | as SQLite |
| Apple's view | Batch writes; avoid many create/delete | Recommended for "frequently changing documents"; use WAL and transactions; don't close connections often ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes), [WWDC19](https://developer.apple.com/videos/play/wwdc2019/419/)) | Recommended likewise |
| Linux tests | Foundation only | Needs libsqlite3 on Linux; not Foundation | Apple platforms only |
| Fit | Append-only, time-ordered, pruned by age | Random update and query; this data needs neither | Object graph; overkill |

- Apple's push to SQLite targets data that is edited in place. Raw is append-only and dropped whole by age, which files serve directly; pruning whole segments costs 8 KB of metadata each ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)).
- Recommendation: segmented append-only files for Raw and Archives. The format and reader live in the Foundation-only core and are tested on Linux; the app layer only owns the file handles, the flush timer and the background task.

## Launch

- The watchdog kills an app that doesn't draw its first frame in time; Apple's example report shows a `scene-create` "wall clock time allowance of 19.97 seconds" ([Addressing watchdog terminations](https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations)). Apple documents no fixed number. "Processing large amounts of data, such as large JSON files" on the main thread is a listed cause.
- Goal: first frame within 400 ms; "avoid blocking the main thread, either with network I/O, file I/O … Move it to a background thread" ([WWDC19 Optimizing App Launch](https://developer.apple.com/videos/play/wwdc2019/423/)). Initialize persistent storage "on first use rather than on app launch" ([Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)).
- 2 h of Raw is 94k results per Link at 13/s, about 1.1 MB at 12 B, 3.7 MB as JSON. Load it in an actor off the main actor after the first frame, as `RollupFiles.load` already runs, and draw the dashboard empty until it lands. Only the newest record is needed before measuring starts (the Pause begin); the rest can follow. Parse speed is *unconfirmed*: measure it.

## For this app

**Pause-begin sequence** (`BlinkengraphsApp` `onChange(of: phase)`, main actor):

1. `.inactive`: begin a named background task (`"Pause"`) if none is open. It stays dormant in the foreground. On `.active`, end it.
2. `.background`: if none is open, begin one now. Stop Rounds and cut the Rounds in flight (spec, "Cut Rounds"). Append a Pause-begin record to the Raw buffer.
3. `Task { await raw.flush(); end the task }`: `flush` is one `FileHandle.write(contentsOf:)` of everything buffered. No `fsync`, no atomic write, no new file.
4. Expiration handler: end the task at once. The handler must not wait for the write; an unfinished flush is covered by the launch rule.
5. On launch, before measuring: read the newest record of the newest segment. If it isn't a Pause-begin, a Pause began at its `at` + 1 (spec). Archives are rebuilt from Raw and Archive files in the background.

**Raw format and cadence:**

- One file per Link per 10 minutes, about 13 files per Link in 2 h; prune by deleting whole files older than `raw_minutes`. One open handle per current segment.
- Fixed-width little-endian binary records, about 12 bytes: `at` (u32 seconds), kind and Probe index (u8 each), Link-local fields, value (u32 µs, or a status code). Pause and Link-change records use the same width with their own kind. Fixed width lets the reader drop a torn tail and find the newest record by seeking from the end.
- Encoding, decoding and tail recovery go in `BlinkengraphsCore`, with the vectors; the app owns only file I/O.
- Flush every 5 s and at Pause begin. That keeps a 5 s margin under the spec's 10 s and bounds writes at about 6 MB/h for one Link, 6–9 MB/h for three (table above). Flushing every 1 s would be about 30 MB/h for no gain.

**Archives:** one append-only file per Archive (A1, A2, A3), one fixed-header record per Row plus its histogram bytes, written once when the Row closes. A1 and A2 are pruned by starting a new file per UTC day (A1) or week (A2) and deleting old files. A3 is a few hundred Rows per key: append, and prune once a day by rewriting it with `Data.write(options: .atomic)`, the only atomic write.

**Measure on a device:**

- Order and spacing of `.inactive`, `.background`, `sceneDidEnterBackground` and `didEnterBackgroundNotification` for Home, app switcher, lock and incoming call; and that the Pause write finishes before suspension (log with `os_signpost`).
- With the background task: time from `.background` to suspension, and that the expiry handler never fires during a normal flush.
- Kill tests: swipe away, `kill -9` from Xcode while foreground and suspended, memory pressure. Confirm the last flushed record is on disk and the next launch shows the right Pause.
- Lock with Require Password Immediately: the Pause write succeeds under the chosen protection class.
- Disk writes for a 1-hour session at 1 and 3 Links: Instruments File Activity, then MetricKit `cumulativeLogicalWrites` and Xcode Organizer after release.
- Launch time with a full 2 h Raw on the oldest supported device: time to first frame and time until graphs fill.
