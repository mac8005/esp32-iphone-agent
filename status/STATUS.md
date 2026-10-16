# Status
Updated: 2026-10-16

## In flight
- Preparing first personal release: ESP32 firmware on MacBook Air and configured iOS TestFlight app.
- Firmware flashed and verified on XIAO ESP32-S3 (8 MB flash/PSRAM), core 3.3.7, NimBLE 2.5.1. Antenna mounted and reconnected by owner.
- iOS simulator tests and firmware host tests passed; GPT-6 request compatibility repaired.
- Apple bundle IDs registered; app record/App Group require web login, using authorized 1Password access.

## Decisions
- Keep provider credentials out of Git; use private internal TestFlight distribution.
- Verify board identity before flashing and exact build testing notes after upload.

## Next
1. Verify running firmware status over serial.
2. Configure vision provider and iOS signing; test and release.
3. Verify firmware boot and TestFlight availability with testing notes.

## Gotchas
- Phone requires cellular data while connected to the board hotspot.
- Initial Bluetooth, screen mirroring, and AssistiveTouch permissions require interaction on the phone.

## Log
- 2026-10-16: Flashed firmware, verified upload hash, passed iOS and host tests; Apple web setup pending.
- 2026-10-16: Created fork and confirmed MacBook Air SSH and attached serial port.
