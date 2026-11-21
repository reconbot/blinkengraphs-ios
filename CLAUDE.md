# blinkengraphs for iOS

Native Swift/SwiftUI. Scope is in `README.md`: network diagnosis only, no system CPU or memory.

The spec repo, reconbot/blinkengraphs, is the authority. Pin a tagged version, and run its vectors in CI:
- `CONTEXT.md`: vocabulary. Use its terms in code and UI.
- `rules/`: Verdict (network half), Probe stats, Hop Trace.
- `vectors/`: conformance tests. An implementation conforms when every vector passes.
- `defaults.json`: Probe Group, intervals, timeouts, history lengths.
- `tokens/`, `fixtures/`: colors and thresholds; data for previews and screenshots.

A rule this app needs but the spec lacks is a spec PR first. The Windows reference implementation (reconbot/blinkengraphs-win) regenerates the vectors.

iOS Local Network Privacy can block Gateway Probes: report them as `denied`, never as loss.

Project memory lives in the repo: decisions `docs/adr/`, research `docs/research/`. Record learnings there.

Skills (`mattpocock-skills`): `domain-modeling` when a term or decision changes, `codebase-design` when shaping a module interface, `tdd` for features and fixes, `writing-for-agents` for any doc or CLAUDE.md edit.

Comments carry only what code can't: the why, the platform gotcha, the source URL. Prose earns each sentence.

Commits follow Conventional Commits. Commits, PRs and comments stay free of session links and personal or employer details; the repo is public.

Never force-push `main` once the repo has a release.
