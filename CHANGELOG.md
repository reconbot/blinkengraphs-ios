# Changelog

## [3.3.0](https://github.com/reconbot/blinkengraphs-ios/compare/v3.2.0...v3.3.0) (2026-11-23)


### Features

* follow spec 6.2.0: platform-neutral Local Metrics, a Pause at first launch, system_dns_domain ([#50](https://github.com/reconbot/blinkengraphs-ios/issues/50)) ([1d76f83](https://github.com/reconbot/blinkengraphs-ios/commit/1d76f83b3dbed7efa9f61f26794712c133af2a1f))


### Bug Fixes

* Targets keep one row each, System DNS measures DNS only; tap a Public Address to copy it ([#46](https://github.com/reconbot/blinkengraphs-ios/issues/46)) ([55c915f](https://github.com/reconbot/blinkengraphs-ios/commit/55c915f1d93ff2ab31977710ec348fbf0b64c84a))
* the latency chart draws off the main actor without trapping ([#49](https://github.com/reconbot/blinkengraphs-ios/issues/49)) ([a6bec5c](https://github.com/reconbot/blinkengraphs-ios/commit/a6bec5c032fa943b1fd770a7adebf3b84a83be1f))

## [3.2.0](https://github.com/reconbot/blinkengraphs-ios/compare/v3.1.0...v3.2.0) (2026-11-23)


### Features

* History that crashes launch twice in a row is deleted ([#44](https://github.com/reconbot/blinkengraphs-ios/issues/44)) ([37ee200](https://github.com/reconbot/blinkengraphs-ios/commit/37ee200ad7e953bbba5fd189fed88fc3cdea69e4))


### Bug Fixes

* launch no longer crashes when no History is saved yet ([#42](https://github.com/reconbot/blinkengraphs-ios/issues/42)) ([789068f](https://github.com/reconbot/blinkengraphs-ios/commit/789068fe83a2a6599e47ae6fd20125ce5363e942))

## [3.1.0](https://github.com/reconbot/blinkengraphs-ios/compare/v3.0.0...v3.1.0) (2026-11-22)


### Features

* a Networks card; the chart shows one network or compares them ([#40](https://github.com/reconbot/blinkengraphs-ios/issues/40)) ([4a8da9f](https://github.com/reconbot/blinkengraphs-ios/commit/4a8da9f90130a8dc100eaddd271c6463e90e01cd))
* History survives a relaunch; a kill leaves a Pause from the last save ([#37](https://github.com/reconbot/blinkengraphs-ios/issues/37)) ([2affa15](https://github.com/reconbot/blinkengraphs-ios/commit/2affa1516aeadb45351f2e9a48f711f415656c01))
* measure every active Link, each pinned to its interface ([#38](https://github.com/reconbot/blinkengraphs-ios/issues/38)) ([0f96625](https://github.com/reconbot/blinkengraphs-ios/commit/0f96625222e394ecb02e5c0c18e806d226bf0b49))

## [3.0.0](https://github.com/reconbot/blinkengraphs-ios/compare/v2.0.0...v3.0.0) (2026-11-22)


### ⚠ BREAKING CHANGES

* stored Rollups are deleted and history restarts empty.

### Features

* clearer Target editor (preset autocomplete, TCP toggle, DNS transport) ([#32](https://github.com/reconbot/blinkengraphs-ios/issues/32)) ([c2b6053](https://github.com/reconbot/blinkengraphs-ios/commit/c2b6053c4001846979341c10873f285669c694cc))
* follow spec 5.2.0: History is Raw plus Archives, Pauses, stats from now ([#35](https://github.com/reconbot/blinkengraphs-ios/issues/35)) ([56f3504](https://github.com/reconbot/blinkengraphs-ios/commit/56f35046c169aeae4e6a55306c77f5d7267138e6))
* Probes wait for the network to settle; MetricKit diagnostics ([#30](https://github.com/reconbot/blinkengraphs-ios/issues/30)) ([066eb9c](https://github.com/reconbot/blinkengraphs-ios/commit/066eb9cc23cfdbcbc8607d60e95cffc84477d628))


### Bug Fixes

* leaving the app no longer clears the graph or reports false loss ([#28](https://github.com/reconbot/blinkengraphs-ios/issues/28)) ([3bdb64d](https://github.com/reconbot/blinkengraphs-ios/commit/3bdb64d9196fc01df4777a7adb8e2e719a290836))

## [2.0.0](https://github.com/reconbot/blinkengraphs-ios/compare/v1.0.0...v2.0.0) (2026-11-22)


### ⚠ BREAKING CHANGES

* the app follows spec 3.0.0: whole-millisecond RTTs, history graphs per rules/history.md, p95 readouts by default.

### Features

* follow spec 3.0.0 ([#27](https://github.com/reconbot/blinkengraphs-ios/issues/27)) ([ef98ccb](https://github.com/reconbot/blinkengraphs-ios/commit/ef98ccb43811484b60c53f267f41eecf4e074b41))
* history follows spec 2.0.0 rules/history.md ([#25](https://github.com/reconbot/blinkengraphs-ios/issues/25)) ([9f2fc23](https://github.com/reconbot/blinkengraphs-ios/commit/9f2fc23659d0860d7092530985c8dad5d8d66327))

## [1.0.0](https://github.com/reconbot/blinkengraphs-ios/compare/v0.1.0...v1.0.0) (2026-11-22)


### Features

* 1h/24h/7d history, p95 graphs and readout settings, smooth scrolling, screenshots on PRs ([#19](https://github.com/reconbot/blinkengraphs-ios/issues/19)) ([aaa56a1](https://github.com/reconbot/blinkengraphs-ios/commit/aaa56a1f24470560ec453358b855cade02af27ca))
* Copy and Share a text report, with a redacted variant; skip translated Hop Traces ([#14](https://github.com/reconbot/blinkengraphs-ios/issues/14)) ([f982da0](https://github.com/reconbot/blinkengraphs-ios/commit/f982da08340eed7663054d197446ec70ce7985ff))
* dashboard redesign, light and dark with a Theme setting, app icon from the spec ([#18](https://github.com/reconbot/blinkengraphs-ios/issues/18)) ([f06bf09](https://github.com/reconbot/blinkengraphs-ios/commit/f06bf09b69e6b4a563c988f96e8ec88057d707db))
* editable Targets, smooth scrolling, system DNS, Captive Portal, Public Address, release-please ([#20](https://github.com/reconbot/blinkengraphs-ios/issues/20)) ([02c79ac](https://github.com/reconbot/blinkengraphs-ios/commit/02c79acc65598c467e157fe8234c44d2ac57417e))
* graph aggregate per-minute storage and histogram ([#11](https://github.com/reconbot/blinkengraphs-ios/issues/11)) ([faa457c](https://github.com/reconbot/blinkengraphs-ios/commit/faa457cd4f63dec7db3669e1573487a30394e7e4))
* ICMP, DNS and Gateway Probes, Hop Trace, and path state ([#6](https://github.com/reconbot/blinkengraphs-ios/issues/6)) ([4ea8a31](https://github.com/reconbot/blinkengraphs-ios/commit/4ea8a31b371f2132279adf20e95391e49d876dee))
* merge defaults.override.json over the spec's shared defaults; pin spec v1.2.0 ([#10](https://github.com/reconbot/blinkengraphs-ios/issues/10)) ([4cd8040](https://github.com/reconbot/blinkengraphs-ios/commit/4cd804034ce03e30b71064add1a2deee6da08c4b))
* name the VPN in the Verdict; collapse a Hop Trace's silent tail; pin spec v1.5.0 ([#16](https://github.com/reconbot/blinkengraphs-ios/issues/16)) ([c90798a](https://github.com/reconbot/blinkengraphs-ios/commit/c90798a78b7691eb88ad943860512c454ba11af0))
* Offline, IPv6 Probes and Hop Trace, per-family Verdict rule, Hop names; pin spec v1.4.0 ([#13](https://github.com/reconbot/blinkengraphs-ios/issues/13)) ([636e743](https://github.com/reconbot/blinkengraphs-ios/commit/636e74346e354eebfa8cf8023baef8a6cd846ef3))
* show cellular radio technology, IPv4/IPv6/DNS support and link quality ([#7](https://github.com/reconbot/blinkengraphs-ios/issues/7)) ([2f20a0a](https://github.com/reconbot/blinkengraphs-ios/commit/2f20a0a92a6d116c12923862c9b077c866937e6b))
* Swift rules engine passing every spec vector, app skeleton, CI ([#5](https://github.com/reconbot/blinkengraphs-ios/issues/5)) ([f701ee3](https://github.com/reconbot/blinkengraphs-ios/commit/f701ee354f631c886ffcde7a4517bd17644edb50))


### Bug Fixes

* a fresh ICMP identifier per echo so concurrent sockets can't take each other's replies ([#17](https://github.com/reconbot/blinkengraphs-ios/issues/17)) ([2ea1592](https://github.com/reconbot/blinkengraphs-ios/commit/2ea15926055e514f5fcb5d406b0763d73b4e731b))
* per-Link History, no Gateway on 464XLAT, ICMP never denied; diagnostics probe Quad9 ([#9](https://github.com/reconbot/blinkengraphs-ios/issues/9)) ([0441708](https://github.com/reconbot/blinkengraphs-ios/commit/044170841ba3e79b0377db72f8dac5e137536dd7))
* report columns fit long hostnames; offline report details; real app version ([#15](https://github.com/reconbot/blinkengraphs-ios/issues/15)) ([01a4d0f](https://github.com/reconbot/blinkengraphs-ios/commit/01a4d0fc47b63b05dd99bb7a81928a73786d2c38))
* TCP Probe uses a BSD socket so IPv4 Targets work on IPv6-only cellular ([#12](https://github.com/reconbot/blinkengraphs-ios/issues/12)) ([9045984](https://github.com/reconbot/blinkengraphs-ios/commit/9045984838236f52650f6b8c52a0f41a43ebc337))
