# 3. Sideload first, App Store later

**Status:** accepted

The first builds install from Xcode with free provisioning (a Personal Team). Signing lives in a git-ignored `Config/Local.xcconfig`; CI builds unsigned.

Consequences:

- **The widget ships now.** It shows the last Verdict, which the app hands over through an App Group (`APP_GROUP`, derived from `BUNDLE_ID_PREFIX`). Apple's [capability table](https://developer.apple.com/help/account/reference/supported-capabilities-ios) lists App Groups for free accounts; the first device build confirms it.
- **Paid-only capabilities stay out:** Access Wi-Fi Information (the SSID) and Network Extensions.
- Free-provisioning installs expire after 7 days and need reinstalling from Xcode.
- The App Store move needs: a paid team, a real bundle ID, signing secrets in CI (fastlane with an App Store Connect API key), and a privacy manifest.
