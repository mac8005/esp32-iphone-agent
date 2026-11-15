# Latest SDK TestFlight rebuild

Updated: 2026-11-15

## Scope

Owner authorized all active iOS apps to their existing TestFlight groups. Rebuild with the newest published Apple SDK, including beta SDKs accepted by TestFlight. Preserve deployment targets, app behavior, identities and audience.

## Verified baseline

- Apple lists Xcode 27.3 beta (27C5020n), iOS SDK 27.3, November 3, 2026.
- Apple App Store Connect release notes allow this SDK for internal and external TestFlight testing.
- Installed and code-signature-verified Xcode 27.3 beta (27C5020n) under ~/Developer/Xcode-27.3-beta/Xcode-beta.app. iOS/watchOS SDK 27.3 verified; now the Mini default. Older Xcodes retained.
- Owner completed the XIP download. Xcodes CLI 2.2.0 installed from the official release ZIP, SHA-256 verified; saved Apple account found, fresh two-factor authentication pending. No code requested in chat.
- App repositories: aura, sidepulse, wardrobe-app, schwab-thinkorswim-t, avinox-lab, blackx-nearby, esp32-iphone-agent, live-translator.

## Next

1. Newest-toolchain selection and archive/IPA app/extension checks implemented; eight guard regression tests pass.
2. Xcode installation and device SDK verification complete.
3. Update actual release notes, build serially, verify exact TestFlight build/group/localizations and signing cleanup.

No release has been completed for this task. Physical-device acceptance remains separate.

Sources: https://developer.apple.com/news/releases/ and https://developer.apple.com/help/app-store-connect/release-notes/
