# blinkengraphs for iOS

A network diagnosis tool for iPhone and iPad: live latency, DNS, path state and a hop trace, with a plain-language Verdict on where the network is failing.

**Status:** in development: the rules engine passes every spec vector; the app probes TCP only so far. The [Windows version](https://github.com/reconbot/blinkengraphs-win) ships today.

## Scope

- Foreground diagnosis:
  - latency to the Gateway, 1.1.1.1 and 8.8.8.8
  - DNS timing
  - `NWPathMonitor` path state
  - a hop trace
  - the network half of the Verdict
- Measures only while the app is open. No widget.
- No system-wide CPU or memory Meters: iOS doesn't expose them to apps.

## Spec

The vocabulary, Verdict rules, test vectors and design tokens live in [reconbot/blinkengraphs](https://github.com/reconbot/blinkengraphs). This app implements them natively, and its CI runs the spec's test vectors.

## Repositories

| Repo | Contents |
|---|---|
| [blinkengraphs](https://github.com/reconbot/blinkengraphs) | Landing page and shared spec |
| [blinkengraphs-win](https://github.com/reconbot/blinkengraphs-win) | Windows 11 app (Rust) |
| [blinkengraphs-mac](https://github.com/reconbot/blinkengraphs-mac) | macOS menu bar app (planned) |
| [blinkengraphs-ios](https://github.com/reconbot/blinkengraphs-ios) | iOS network diagnosis app (planned) |

## Building

Needs Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone --recurse-submodules https://github.com/reconbot/blinkengraphs-ios
cd blinkengraphs-ios
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your team and bundle ID prefix
xcodegen generate
open Blinkengraphs.xcodeproj
```

The rules engine is a plain Swift package and runs the spec's vectors anywhere Swift runs, Linux included:

```bash
swift test --package-path BlinkengraphsKit
```

| Path | Contents |
|---|---|
| `spec/` | The spec, pinned to a release tag as a git submodule |
| `BlinkengraphsKit/` | `BlinkengraphsCore`: Probe stats, Hop Trace, Meters, Verdict. Foundation only |
| `App/` | The SwiftUI app: probing and UI |
| `project.yml` | XcodeGen project spec; the `.xcodeproj` is generated |
| `docs/adr/` | Decisions |
