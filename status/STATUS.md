# Status
Updated: 2026-10-16

## In flight
- Preparing first personal release: ESP32 firmware on MacBook Air and configured iOS TestFlight app.
- Fork created from upstream main at 9b1a667; MacBook Air reachable with /dev/cu.usbmodem101.

## Decisions
- Keep provider credentials out of Git; use private internal TestFlight distribution.
- Verify board identity before flashing and exact build testing notes after upload.

## Next
1. Identify attached board and build firmware.
2. Configure vision provider and iOS signing; test and release.
3. Verify firmware boot and TestFlight availability with testing notes.

## Gotchas
- Phone requires cellular data while connected to the board hotspot.
- Initial Bluetooth, screen mirroring, and AssistiveTouch permissions require interaction on the phone.

## Log
- 2026-10-16: Created fork and confirmed MacBook Air SSH and attached serial port.
