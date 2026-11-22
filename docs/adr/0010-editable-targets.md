# 10. Editable Targets, as on Windows, without UDP

**Status:** accepted

Settings → Targets edits the Probe Group, following blinkengraphs-win's editor. Each Target is an address, a host name, `gateway` or `system-dns`, with ICMP, a TCP port, DNS and Hop Trace, plus the Latency and Hop Trace intervals. It is stored as JSON in user defaults; empty means the spec's group, so a spec bump still updates users who never edited it.

- **No UDP column.** The app has no UDP Probe, so a UDP port would be stored and never measured. Add it with a UDP runner.
- **One group.** Windows allows several; the Verdict and graphs here assume one, and nothing on iOS has asked for more yet.
- **Names** are resolved through the system resolver every 30 s (spec `CONTEXT.md` "Target"), IPv6 first when the path has IPv6. A name that doesn't resolve is skipped, never counted as loss.
- **TargetLayout** (core) derives names, order, the charted Probe and colour slots from the group, so the screen, the report and redaction follow an edit together.
- **The editor** offers `gateway` and `system-dns` as rows under the Target field while what's typed matches the keyword or its name (`TargetLayout.presets(completing:)`): nobody guesses a keyword. TCP is a toggle like the others, and turning it on shows the Port field filled with 443, the port the spec's Targets use; a bare field hinted "off" didn't read as an input. The DNS toggle names what it sends, "UDP 53" or the system resolver, since the transport and port are fixed.
