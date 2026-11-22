# Device tests

What CI and the Simulator can't show. Each result goes into `docs/research/`, and the ADR named beside it takes the measured value. A sideloaded build from `main` is enough (ADR 0003).

| # | Test | How | Sets |
|---|---|---|---|
| 1 | Settle time after a return to the app | On Wi-Fi, cellular and a VPN: leave for 1 min, 10 min and 1 h, return, and note how long until every Target card shows a number with no loss | ADR 0015's 2 s |
| 2 | Lifecycle order | Leave by Home, the app switcher, the lock button and an incoming call; check the Pause in History starts within a second of leaving | ADR 0016 |
| 3 | Kill | Force-quit from the app switcher, and run Xcode's memory-warning loop until iOS ends the app; relaunch: the gap draws as Paused, starting at the last save | ADR 0016 |
| 4 | Pause written under lock | Settings → Face ID & Passcode → Require Passcode Immediately; lock the phone with the app open; reopen: no gap missing its Pause | ADR 0016 |
| 5 | Write volume | A 1 h session at the 5 s cadence; MetricKit `MXDiskIOMetric` from the Report menu's diagnostics. The estimate is about 6 MB an hour | ADR 0016 |
| 6 | Launch with 2 h of Raw | Measure 2 h, kill, relaunch: time to first frame and to the first Round | ADR 0016 |
| 7 | Cellular beside Wi-Fi | Turn on "Measure cellular while on Wi-Fi": the Cellular row fills in, and Settings → Cellular shows the app's data. Compare with the 20–55 MB an hour the switch quotes | ADR 0017, the switch's text |
| 8 | Per-app cellular off | Settings → Cellular → blinkengraphs off, then turn the app's switch on: the row must not read as loss | ADR 0017 |
| 9 | VPN | A full-tunnel and a split-tunnel VPN: the Verdict names VPN, the Gateway still reads (from Wi-Fi), and Targets outside a split tunnel aren't measured on it | ADR 0017 |
| 10 | iCloud Private Relay | On and off: does a VPN row appear, and does System DNS change | ADR 0017 |

The nine binding tests in `docs/research/multi-link-probing.md` ("For this app") go deeper on 7–10.
