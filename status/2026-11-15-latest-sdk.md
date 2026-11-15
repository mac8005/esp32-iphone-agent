# Latest SDK TestFlight rebuild

Updated: 2026-11-15

## Scope

Owner authorized all active iOS apps to their existing TestFlight groups. Rebuild with the newest published Apple SDK, including beta SDKs accepted by TestFlight. Preserve deployment targets, app behavior, identities and audience.

## Verified baseline

- Apple lists Xcode 27.3 beta (27C5020n), iOS SDK 27.3, November 3, 2026.
- Apple App Store Connect release notes allow this SDK for internal and external TestFlight testing.
- Installed and code-signature-verified Xcode 27.3 beta (27C5020n) under ~/Developer/Xcode-27.3-beta/Xcode-beta.app. iOS/watchOS SDK 27.3 verified; now the Mini default. Older Xcodes retained.
- Owner completed the XIP download. Xcodes CLI 2.2.0 installed from the official release ZIP, SHA-256 verified; saved Apple account found, SMS authentication and actual unattended download verified; daily updater installed in mac-maintenance.
- App repositories: aura, sidepulse, wardrobe-app, schwab-thinkorswim-t, avinox-lab, blackx-nearby, esp32-iphone-agent, live-translator.

## Release complete

- Version 1.0.16 (16), source f33c42a.
- Independently verified VALID, IN_BETA_TESTING, existing Personal Testing group and exact What to Test in zh-Hans, en-US. [Receipt](2026-11-15-sdk27.3-build16.json).
- Signed archive/export and exact app/extension SDK 27.3 / Xcode 27C5020n checks passed. Existing signing identity and profiles preserved; keychain search list restored and lock released. Artifacts: ~/Developer/esp32-iphone-agent/releases/1.0.16-16. Board firmware and physical device state were unchanged.
- Physical-device compatibility checks remain unobserved. TestFlight availability is verified separately from physical acceptance.

Sources: https://developer.apple.com/news/releases/ and https://developer.apple.com/help/app-store-connect/release-notes/
