# 2. The spec is pinned as a git submodule

**Status:** accepted

`spec/` is reconbot/blinkengraphs checked out at a release tag. Tests read `spec/vectors/` from disk; the app bundles `spec/defaults.json` and `spec/tokens/blinkengraphs.tokens.json` as resources and decodes them at launch.

- It needs no change to the spec repo. A SwiftPM resource package would need a `Package.swift` there.
- Bumping the spec is one commit: `git -C spec checkout vX.Y.Z`, then commit the new gitlink.
- Clone with `--recurse-submodules`, or run `git submodule update --init`.

Revisit when the Mac app exists: both Swift apps could then share a SwiftPM package of the spec's resources.
