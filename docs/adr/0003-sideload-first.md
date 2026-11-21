# 3. Sideload first, App Store later

**Status:** accepted

The first builds install from Xcode with free provisioning (a Personal Team). Signing lives in a git-ignored `Config/Local.xcconfig`; CI builds unsigned.

Consequences:

- **No widget yet.** The README's widget shows the last Verdict, which the app must hand over through an App Group. Whether free provisioning allows App Groups is unconfirmed ([supported capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios)), so the widget and the App Group arrive together with the paid team.
- Free-provisioning installs expire after 7 days and need reinstalling from Xcode.
- The App Store move needs: a paid team, a real bundle ID, the App Group, signing secrets in CI, and a privacy manifest.
