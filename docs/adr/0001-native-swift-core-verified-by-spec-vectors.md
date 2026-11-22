# 1. A Foundation-only Swift core, verified by the spec vectors

**Status:** accepted

`BlinkengraphsKit/Sources/BlinkengraphsCore` implements Probe stats, the Hop Trace table, Meter scaling and the Verdict in Swift with Foundation only. Platform code (Network.framework, sockets, SwiftUI) lives in the app target and feeds it.

- Foundation-only means `swift test` runs every spec vector on Linux as well as macOS, so the rules can be checked without Xcode.
- The core also implements the Local rules. iOS never supplies a Sample with CPU or memory Metrics, so they never fire on device, but implementing them makes "every vector passes" literally true instead of needing an exclusion list.

## Semantics the vectors require but `rules/verdict.md` does not state

- **Worst-Probe ties go to the first Probe** in Probe Group order, comparing loss as shown, a whole percent. Spec 4.0.0 made this a rule (`verdict.md`, vector `isp-loss-tie`); it used to be the last.
- **Rule 1 also suppresses the DNS rule** (vector `lan-down`: system DNS at 100% loss, no DNS Finding).

The second belongs in the spec's prose; until then it is pinned here and by the vectors.
