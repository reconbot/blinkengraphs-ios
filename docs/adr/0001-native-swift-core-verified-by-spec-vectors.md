# 1. A Foundation-only Swift core, verified by the spec vectors

**Status:** accepted

`BlinkengraphsKit/Sources/BlinkengraphsCore` implements Probe stats, the Hop Trace table, Meter scaling and the Verdict in Swift with Foundation only. Platform code (Network.framework, sockets, SwiftUI) lives in the app target and feeds it.

- Foundation-only means `swift test` runs every spec vector on Linux as well as macOS, so the rules can be checked without Xcode.
- The core also implements the Local rules. iOS never supplies a Sample with CPU or memory Metrics, so they never fire on device, but implementing them makes "every vector passes" literally true instead of needing an exclusion list.

## Semantics the vectors require but `rules/verdict.md` does not state

- **Worst-Probe ties go to the last Probe** in input order. The reference uses Rust's `max_by`, which returns the last maximum (vector `isp-loss`: every Internet Probe at 23%, headline names `8.8.8.8`).
- **Rule 1 also suppresses the DNS rule** (vector `lan-down`: system DNS at 100% loss, no DNS Finding).

Both belong in the spec's prose; until then they are pinned here and by the vectors.
