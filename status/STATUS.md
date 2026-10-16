# Status
Updated: 2026-10-16

## In flight
- Release complete: ESP32 Agent 1.0.1 (1) is IN_BETA_TESTING / Ready to Test for Personal Testing; account holder invited.
- User confirmed calibration succeeds, but tasks appear idle on Home Screen. Uploaded trace shows delayed startup and stale/corrupted video; physical control remains unverified.

## Decisions
- Keep provider credentials out of Git; use private internal TestFlight distribution.
- GPT-6.1 Sol with low reasoning: matched Astra on three screenshot tasks, median 4.2 s vs 4.59 s in the small benchmark.
- Provider key stored encrypted on board; wrapping key in ignored personal build config. Pairing imports into iPhone Keychain. Possession of both personal app and board permits recovery; this is not hardware-backed protection.
- Reuse SidePulse retained certificate and shared signing lock; create only this app's profiles. Personal release script publishes and reads back en-US/zh-Hans notes.
- Verify board identity before flashing and exact build testing notes after upload.

## Next
1. Diagnose video backlog/replay and decoder recovery using live Diagnostics; trace export lacks debug.log.
2. Verify fresh, intact post-action frames and actual phone control before declaring the runtime working.

## Gotchas
- Internal testers must be added through Apple's web interface; an external betaTester record with the same email cannot be assigned. Future releases reuse the existing internal member.
- Resume an uploaded release with .testflight/deploy-personal.py VERSION BUILD --finalize-only.
- Phone requires cellular data while connected to the board hotspot.
- Initial Bluetooth, screen mirroring, and AssistiveTouch permissions require interaction on the phone.
- USB CDC input buffer is 256 bytes; provisioning script sends 64-byte chunks. Never log decrypted keys.

## Log
- 2026-10-16: Inspected user trace: first planner record at +180.7 s (request 3.02 s), later reported frame offsets -183.63 to -198.26 s, visible corruption in 006.jpg. Model replies succeed; root transport/decoder trigger remains unproven. No firmware/app fix deployed.
- 2026-10-16: Released 1.0.1 (1), build 8a7f8276-ffcf-4ac4-b6bf-9c06504712d5. Verified IN_BETA_TESTING, owner membership, and exact en-US/zh-Hans notes; history in .testflight/releases/1.0.1-1.json.
- 2026-10-16: Signed archive/export passed, upload started. Board credential survived restart and decrypted correctly.
- 2026-10-16: Recovered Safari, completed Apple capabilities/profiles, provisioned board, passed 83 signed simulator tests.
- 2026-10-16: Flashed firmware, verified upload hash, passed iOS and host tests; Apple web setup pending.
- 2026-10-16: Created fork and confirmed MacBook Air SSH and attached serial port.
