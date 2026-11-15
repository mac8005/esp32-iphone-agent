# Latest SDK TestFlight rebuild

Updated: 2026-11-15

## Scope

Owner authorized all active iOS apps to their existing TestFlight groups. Rebuild with the newest published Apple SDK, including beta SDKs accepted by TestFlight. Preserve deployment targets, app behavior, identities and audience.

## Verified baseline

- Apple lists Xcode 27.3 beta (27C5020n), iOS SDK 27.3, November 3, 2026.
- Apple App Store Connect release notes allow this SDK for internal and external TestFlight testing.
- MacMini8005 defaults to Xcode 27.1 and also has Xcode 27.2.
- Download requires an authenticated Apple Developer session; automated download timed out. Owner asked to save the XIP under ~/Developer/xcode-xips/.
- App repositories: aura, sidepulse, wardrobe-app, schwab-thinkorswim-t, avinox-lab, blackx-nearby, esp32-iphone-agent, live-translator.

## Next

1. Require and select newest published toolchain in release entry points, verify packaged SDK before upload.
2. Install and verify Xcode 27.3 beta and device platform SDKs.
3. Update actual release notes, build serially, verify exact TestFlight build/group/localizations and signing cleanup.

No release has been completed for this task. Physical-device acceptance remains separate.

Sources: https://developer.apple.com/news/releases/ and https://developer.apple.com/help/app-store-connect/release-notes/
