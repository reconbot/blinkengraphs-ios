# 11. Releases as on Windows: tagged by release-please, plus a rolling main-latest

**Status:** accepted

This follows blinkengraphs-win's ADR 0005. release-please cuts tagged releases from Conventional Commits and writes the version into `project.yml` `MARKETING_VERSION`. Every push to `main` also rebuilds and overwrites a `main-latest` prerelease. Each tagged release gets the commit's CI screenshots appended to its notes.

- **The download is an unsigned IPA.** Without a paid developer account there is nothing to sign it with (ADR 0003). Sideloading tools such as AltStore and Sideloadly sign it with the installer's own Apple ID; building from source in Xcode works too.
- **Build-provenance attestations** (`actions/attest`) let `gh attestation verify` check that an IPA came from this repository's CI.
- **App Store and TestFlight** wait for the paid account.
