# Status
Updated: 2026-10-16

## In flight
- 1.0.2 (2) failed on the phone: no current post-Home frame. New logs also show calibration accepted a 49.8% miss.
- 1.0.3 (3) IN_BETA_TESTING with localized notes verified; all 87 tests passed. Replacement 1.0.4 (4) retains streaming across calibration/task completion; all 87 tests pass, uploaded successfully; waiting for Apple processing and TestFlight finalization.
- MBA USB board flashed with heartbeat/debug video-throttling repair; upload checksum verified, USB ok after reboot, encrypted credential retained.
- MBA Terminal BLE benchmarks pass: 128 KB at 200 kbps, 256 KB with 0.5 s pings at 195 kbps, zero gaps; ping replies 54–145 ms. iOS 27.2 beta end-to-end success remains unverified.

## Decisions
- Keep provider credentials out of Git; use private internal TestFlight distribution.
- GPT-6.1 Sol with low reasoning: matched Astra on three screenshot tasks, median 4.2 s vs 4.59 s in the small benchmark.
- Provider key stored encrypted on board; wrapping key in ignored personal build config. Pairing imports into iPhone Keychain. Possession of both personal app and board permits recovery; this is not hardware-backed protection.
- Reuse SidePulse retained certificate and shared signing lock; create only this app's profiles. Personal release script publishes and reads back en-US/zh-Hans notes.
- Verify board identity before flashing and exact build testing notes after upload.

## Next
1. Finalize uploaded replacement 1.0.4 (4), delivery 5e119d9b-c724-407f-8ca9-f598fffd02b3; verify localized notes and availability.
2. Verify fresh Home frames and real phone actions; do not equate guard failures or upload success with a working agent.

## Gotchas
- Internal testers must be added through Apple's web interface; an external betaTester record with the same email cannot be assigned. Future releases reuse the existing internal member.
- Resume an uploaded release with .testflight/deploy-personal.py VERSION BUILD --finalize-only.
- Phone requires cellular data while connected to the board hotspot.
- Initial Bluetooth, screen mirroring, and AssistiveTouch permissions require interaction on the phone.
- USB CDC input buffer is 256 bytes; provisioning script sends 64-byte chunks. Never log decrypted keys.

## Log
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
- 2026-10-16: Released 1.0.1 (1), build 8a7f8276-ffcf-4ac4-b6bf-9c06504712d5. Verified IN_BETA_TESTING, owner membership, and exact en-US/zh-Hans notes; history in .testflight/releases/1.0.1-1.json.
- 2026-10-16: Signed archive/export passed, upload started. Board credential survived restart and decrypted correctly.
- 2026-10-16: Recovered Safari, completed Apple capabilities/profiles, provisioned board, passed 83 signed simulator tests.
