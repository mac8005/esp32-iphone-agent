# Status
Updated: 2026-10-23

## In flight
- ESP32 firmware updated on MBA; upload checksum, USB health and encrypted credential retention verified.
- ESP32 Agent 1.0.6 (6) IN_BETA_TESTING (calibration edge-sample fix + delayed-video catch-up wait); en-US/zh-Hans notes verified. Receipt: .testflight/releases/1.0.6-6.json. Firmware unchanged. Awaiting phone test.
- All 87 simulator tests pass. MBA BLE: 200 kbps idle, 195 kbps with 0.5 s pings, zero gaps, replies 54–145 ms.
- Physical iOS 27.2 beta success remains unverified. Old calibration with 49.8% error is rejected and requires recalibration; earlier screenshot had Snap to Item on.

## Decisions
- Video latency root cause (2026-10-23 log): board forwards every AU in order over BLE (110–135 kbps that day, 200–230 on 10-17); AirPlay bursts of 260–610 kbps at screen transitions queue 20–40 s. App now waits while frames keep advancing (max 90 s). Real fix candidates: lower AirPlay resolution/fps advertised by the board, or raise BLE throughput (Wi-Fi coexistence).
- Keep provider credentials out of Git; use private internal TestFlight distribution.
- GPT-6.1 Sol with low reasoning: matched Astra on three screenshot tasks, median 4.2 s vs 4.59 s in the small benchmark.
- Provider key stored encrypted on board; wrapping key in ignored personal build config. Pairing imports into iPhone Keychain. Possession of both personal app and board permits recovery; this is not hardware-backed protection.
- Reuse SidePulse retained certificate and shared signing lock; create only this app's profiles. Personal release script publishes and reads back en-US/zh-Hans notes.
- Verify board identity before flashing and exact build testing notes after upload.

## Next
1. Verify accurate calibration with Snap to Item off, fresh Home frames and real phone actions on 1.0.6 (6) after recalibrating.
2. If still failing, inspect startup video metrics; keep board transport and iOS background decoding evidence separate. Do not claim the agent works from a successful upload or Mac BLE benchmark.

## Gotchas
- Internal testers must be added through Apple's web interface; an external betaTester record with the same email cannot be assigned. Future releases reuse the existing internal member.
- Run deploy-personal.py from a Terminal .command opened in the mini GUI session; over plain SSH the login keychain is locked (security exit 36). Simulator 825CA8B2 is gone; tests use iPhone 17 572A4F80.
- Resume an uploaded release with .testflight/deploy-personal.py VERSION BUILD --finalize-only.
- Phone requires cellular data while connected to the board hotspot.
- Initial Bluetooth, screen mirroring, and AssistiveTouch permissions require interaction on the phone.
- USB CDC input buffer is 256 bytes; provisioning script sends 64-byte chunks. Never log decrypted keys.

## Log
- 2026-10-23: Phone log analysis: calibration check skew = edge-clamped probe tap kept in pointer correction (x 113 vs 90 units); video failures = BLE backlog after AirPlay bursts outlasting the 15 s wait. Fixed both (0db4434), 89/89 tests, new tests fail on old code. Released 1.0.6 (6), build aadbaff0-37e3-45b0-94c2-193b38e336e4, notes verified.
- 2026-10-23: Ported upstream 6dec6a6 (MetricKit launch crash) and 133ead5 (flash port). 87/87 tests pass. Released 1.0.5 (5), build 3caf4c63-bff6-45ab-99d5-5329e5b154e3, IN_BETA_TESTING; notes verified. Other upstream commits (docs, NOTICE, fastlane) not taken.
- 2026-10-16: Released 1.0.4 (4), build 5e119d9b-c724-407f-8ca9-f598fffd02b3, IN_BETA_TESTING. Personal Testing membership and exact en-US/zh-Hans notes verified. All 87 tests pass; physical iOS 27.2 beta validation pending.
- 2026-10-16: 1.0.3 (3) IN_BETA_TESTING and en-US/zh-Hans notes verified; receipt saved. Replacement 1.0.4 (4) upload accepted, awaiting Apple processing.
- 2026-10-16: Replacement 1.0.4 (4), commit 575f6d0, passes all 87 tests. Release pipeline started; no further firmware changes needed.
- 2026-10-16: Final lifecycle review found explicit stream stops after calibration and task completion would replay history on next warmup. Removed these in streaming mode; preparing replacement 1.0.4 (4), tests running.
- 2026-10-16: Apple accepted 1.0.3 (3). On-board BLE tests pass at 200 kbps idle and 195 kbps with 0.5 s heartbeat traffic, zero gaps, 54–145 ms replies. SSH Bluetooth is denied; launch diagnostics as a Terminal .command via open on MBA.
- 2026-10-16: Firmware checksum and post-flash USB/credential retention verified on MBA. All 87 simulator tests pass; 1.0.3 (3) archive signed successfully and release pipeline running. Commit 868dd47.
- 2026-10-16: Latest log confirms 49.8% calibration error accepted and startup video stale. Prepared calibration rejection, setup video reception, and firmware heartbeat/debug throttle exemption. MBA USB connected; BLE diagnostics blocked by macOS privacy permission.
- 2026-10-16: Released 1.0.2 (2), build 1bbaa089-d18d-46df-91a6-b499ffe19a16. Verified IN_BETA_TESTING, Personal Testing membership, and exact en-US/zh-Hans notes. Receipt: .testflight/releases/1.0.2-2.json.
- 2026-10-16: Apple accepted 1.0.2 (2) upload (delivery 1bbaa089-d18d-46df-91a6-b499ffe19a16). Finalizer resumed using release Python environment; exact notes and internal availability still pending.
- 2026-10-16: Fixed startup snapshot fallback, stale frame acceptance, reconnect frame retention, and missing-keyframe recovery. Regression tests failed before repair; all 86 tests pass after. Prepared 1.0.2 (2) notes; firmware unchanged.
- 2026-10-16: Full log confirms 18:55 run waited 167217 ms for snap, starting agent at +177672 ms. USB ok, strong BLE RSSI, model HTTP 200 in 2-3 s. Repeated background decoder invalidation (-12903); earlier snaps ended in BLE disconnect after 84/108 s. No fix deployed yet.
- 2026-10-16: Checked all upstream issues/comments and PRs. #12 reports a different streaming-with-zero-media bug; no matching fix or confirmed iOS 27.2 regression found. Fork includes latest upstream 9b1a667. Need full log export, not another trace-only ZIP.
- 2026-10-16: Inspected user trace: first planner record at +180.7 s (request 3.02 s), later reported frame offsets -183.63 to -198.26 s, visible corruption in 006.jpg. Model replies succeed; root transport/decoder trigger remains unproven. No firmware/app fix deployed.
