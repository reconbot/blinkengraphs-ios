# 3. Sideload first, App Store later

**Status:** accepted

The first builds install from Xcode with free provisioning (a Personal Team). Signing lives in a git-ignored `Config/Local.xcconfig`; CI builds unsigned.

Consequences:

- Paid-only capabilities stay out: Access Wi-Fi Information (the SSID) and Network Extensions.
- Free-provisioning installs expire after 7 days and need reinstalling from Xcode.
- The App Store move needs: a paid team, a real bundle ID, the App Group, signing secrets in CI (fastlane with an App Store Connect API key), and a privacy manifest.
