# 4. Measure only while the app is open

**Status:** accepted

Probes run while the app is in the foreground and stop when it leaves. There is no widget and no Live Activity.

A Live Activity would not keep Probes running:

- It grants no background execution. Updates come from the app while it runs, or from ActivityKit push notifications, which need a server and a paid team. "Unlike a widget, a Live Activity can't access the network" ([Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)).
- It is rendered by a widget extension, which this app does not ship.
- It lasts at most 8 hours.

The background modes don't fit continuous measurement either:

- `BGAppRefreshTask` runs when the system chooses.
- `BGProcessingTask` runs only while the device is idle ([BackgroundTasks](https://developer.apple.com/documentation/backgroundtasks)).
- `BGContinuedProcessingTask` (iOS 26) is for user-started work with an end, not an open-ended monitor.

Revisit if users ask for a "keep watching for N minutes" mode. `BGContinuedProcessingTask` is the candidate for that mode, and it would need iOS 26.
