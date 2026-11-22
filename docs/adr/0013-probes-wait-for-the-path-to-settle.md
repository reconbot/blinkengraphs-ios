# 13. Probes wait for the path to settle

**Status:** accepted; amended by ADR 0015: a return to the app is a Pause with its own settle time, and this quiet period applies to route changes only

The first results after a network change measured the switch, not the network. A device going from Wi-Fi to cellular showed early spikes and losses, and after a return to the app the first rounds ran on the path from before the pause, filed under the wrong Link.

Probes, Hop Traces and the lookups now start only once the path has settled (`PathSettle`). Settled means NWPathMonitor has reported a working route and that route has held for a quiet period. A route is the Link, whether the path is up, and its IPv4 and IPv6 support; changes in link quality or cost don't count. Launch, a return to the app and every route change start the wait again. A round still in flight when the route changes is dropped, like one cut off by a pause (ADR 0012), so nothing measured across the switch is recorded.

The quiet period is 1 s, a first guess to tune from device results. If early results still spike once the wait is in place, the next step is to drop the first results after the path settles too. That would be a shared rule, so it goes to the spec first.
