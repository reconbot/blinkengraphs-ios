# 6. Shared defaults with a platform override file

**Status:** accepted

The spec's `defaults.json` holds the defaults every platform shares, and the spec owns it. This app bundles it from the pinned `spec/` and merges `defaults.override.json` over it at launch (`Defaults.decode(_:override:)`), following the spec's `rules/defaults.md`. The merge passes the spec's `vectors/defaults/merge.json`.

- `defaults.override.json` is `{}`: iOS overrides nothing yet. Each future override records its reason here.
- Overriding `max_timeout_ms`, `hop_trace` or `history.recent_window_s` takes effect, because the app reads them from `Defaults`.
