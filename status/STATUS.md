# Status
Updated: 2026-10-16

## In flight
- Preparing first personal release: ESP32 firmware on MacBook Air and configured iOS TestFlight app.
- Firmware flashed and verified on XIAO ESP32-S3 (8 MB flash/PSRAM), core 3.3.7, NimBLE 2.5.1. Antenna mounted and reconnected by owner.
- 83 signed iOS simulator tests passed, including authenticated preset import and Keychain persistence.
- Apple app 6823679885 created; both bundle IDs assigned group.com.massimo.esp32agent. Distribution profiles and all required entitlements verified.
- Firmware reflashed with USB provisioning/status commands. Encrypted credential read back and decrypted successfully; USB ok, hotspot AP, 3.37 MB free PSRAM, configuration 353 bytes.
- TestFlight 1.0.1 (1) archive/export succeeded; package verified free of provider API key. Upload running; processing, owner availability, and localized notes remain pending.

## Decisions
- Keep provider credentials out of Git; use private internal TestFlight distribution.
- GPT-6.1 Sol with low reasoning: matched Astra on three screenshot tasks, median 4.2 s vs 4.59 s in the small benchmark.
- Provider key stored encrypted on board; wrapping key in ignored personal build config. Pairing imports into iPhone Keychain. Possession of both personal app and board permits recovery; this is not hardware-backed protection.
- Reuse SidePulse retained certificate and shared signing lock; create only this app's profiles. Personal release script publishes and reads back en-US/zh-Hans notes.
- Verify board identity before flashing and exact build testing notes after upload.

## Next
1. Monitor release-driver.log under /Volumes/MacMiniData/Developer/esp32-iphone-agent; release script is uploading 1.0.1 (1).
2. Verify exact build available to account holder and testing notes.
3. Record release. Physical phone pairing/mirroring/AssistiveTouch/calibration remain first-use steps.

## Gotchas
- Phone requires cellular data while connected to the board hotspot.
- Initial Bluetooth, screen mirroring, and AssistiveTouch permissions require interaction on the phone.
- USB CDC input buffer is 256 bytes; provisioning script sends 64-byte chunks. Never log decrypted keys.

## Log
- 2026-10-16: Signed archive/export passed, upload started. Board credential survived restart and decrypted correctly.
- 2026-10-16: Recovered Safari, completed Apple capabilities/profiles, provisioned board, passed 83 signed simulator tests.
- 2026-10-16: Flashed firmware, verified upload hash, passed iOS and host tests; Apple web setup pending.
- 2026-10-16: Created fork and confirmed MacBook Air SSH and attached serial port.
