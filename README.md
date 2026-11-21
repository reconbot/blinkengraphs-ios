# blinkengraphs for iOS

A network diagnosis tool for iPhone and iPad: live latency, DNS, path state and a hop trace, with a plain-language Verdict on where the network is failing.

**Status:** not started. The [Windows version](https://github.com/reconbot/blinkengraphs-win) ships today.

## Scope

- Foreground diagnosis:
  - latency to the Gateway, 1.1.1.1 and 8.8.8.8
  - DNS timing
  - `NWPathMonitor` path state
  - a hop trace
  - the network half of the Verdict
- A widget that shows the last Verdict. iOS budgets widget refreshes, so it isn't a live graph.
- No system-wide CPU or memory Meters: iOS doesn't expose them to apps.

## Spec

The vocabulary, Verdict rules, test vectors and design tokens live in [reconbot/blinkengraphs](https://github.com/reconbot/blinkengraphs). This app implements them natively, and its CI runs the spec's test vectors.
