# blinkengraphs for iOS

Native Swift/SwiftUI. Scope is in `README.md`: network diagnosis only, no system CPU or memory.

The spec repo, reconbot/blinkengraphs, is the authority. Pin a tagged version, and run its vectors in CI:
- `CONTEXT.md`: vocabulary. Use its terms in code and UI.
- `rules/`: Verdict (network half), Probe stats, Hop Trace, Graph aggregate, Defaults.
- `vectors/`: conformance tests. An implementation conforms when every vector passes.
- `defaults.json`: shared Probe Group, intervals, timeouts, history lengths. `defaults.override.json` here merges over it (`rules/defaults.md`); each override needs an ADR.
- `tokens/`, `fixtures/`: colors (dark, plus a light palette) and thresholds; data for previews and screenshots.
- `brand/icon.svg`: the app icon, rendered into the asset catalog at build time.

Changes that touch more than one repo follow the spec's `docs/sync.md`: bump the pinned spec tag in a PR whenever the spec releases.

A rule this app needs but the spec lacks is a spec PR first, with its vectors.

iOS Local Network Privacy gates TCP and UDP to the LAN, not ICMP (`docs/research/local-network-privacy.md`). A Probe it blocks is `denied`, never loss.

Project memory lives in the repo: decisions `docs/adr/`, research `docs/research/`. Record learnings there.

Skills (`mattpocock-skills`): `domain-modeling` when a term or decision changes, `codebase-design` when shaping a module interface, `tdd` for features and fixes, `writing-for-agents` for any doc or CLAUDE.md edit.

Comments carry only what code can't: the why, the platform gotcha, the source URL. Prose earns each sentence.

Commits follow Conventional Commits. Commits, PRs and comments stay free of session links and personal or employer details; the repo is public.

Never force-push `main` once the repo has a release.

Release PRs (release-please) merge only after the owner has reviewed them and said so. Feature PRs merge when tests pass.
