# Status
Updated: 2026-10-23

## In flight
- ESP32 firmware updated on MBA; upload checksum, USB health and encrypted credential retention verified.
- ESP32 Agent 1.0.15 (15) IN_BETA_TESTING + firmware flashed 2026-10-23 (constant-speed straight moves via src/motion/stroke.c, new `path` stroke command; hash verified, NVS config + sealed key kept). App: check tap before every run (recalibrates on >1.5% miss), drags as one `path`, aim only after a miss, return-to-app via Home + OCR Search field + result (frames saved to Documents/return/). Receipt .testflight/releases/1.0.15-15.json. Phone behaviour UNVERIFIED.
- All 87 simulator tests pass. MBA BLE: 200 kbps idle, 195 kbps with 0.5 s pings, zero gaps, replies 54–145 ms.
- Physical iOS 27.2 beta success remains unverified. Old calibration with 49.8% error is rejected and requires recalibration; earlier screenshot had Snap to Item on.

## Decisions
- Pointer model (fit on 252 probes, scratch analysis 2026-10-23): iOS gain depends on report speed; old per-axis capping gave diagonal reports 14 units vs 10, stretching axes per move (per-axis line residual up to 4%, report-speed model 0.1-0.6%). Firmware now sends equal 10-unit reports along a straight line. Start corner usually (18,18) pt but shifted to (-4,-4) in one session -> check tap before every run.
- Decisions API candidate (not built): OpenAI POST /v1/decisions, model gpt-6-luna, accepts images, returns choice/predicate/score with confidence (GA 2026-10-22). Probe 2026-10-23 with real screenshots + on-device Vision OCR labels as choices: 420-590 ms vs 2.3-3.6 s actor, picked Search (conf 0.48 vs other 0.47) and Notes result (conf 0.99). Plan: OCR candidates -> Decisions choice; act when confident, else fall back to the current actor. Jev (TypeSafe) is text-only, unusable for screen decisions.
- 2026-10-23 run breakdown (1.0.7): per step LLM 2.3-3.6 s (TTFT ~2.3 s, 178 KB image), HID 0.4-1.5 s, frame <0.6 s. Waste = missed taps (manual 1-point calibration lacks offset) + iOS stopping mirroring mid-run (~90 s). App already supports separate planner/actor models (Settings.client(role)).
- Video latency root cause (2026-10-23 log): board forwards every AU in order over BLE (110–135 kbps that day, 200–230 on 10-17); AirPlay bursts of 260–610 kbps at screen transitions queue 20–40 s. App now waits while frames keep advancing (max 90 s). Real fix candidates: lower AirPlay resolution/fps advertised by the board, or raise BLE throughput (Wi-Fi coexistence).
- Keep provider credentials out of Git; use private internal TestFlight distribution.
- GPT-6.1 Sol with low reasoning: matched Astra on three screenshot tasks, median 4.2 s vs 4.59 s in the small benchmark.
- Provider key stored encrypted on board; wrapping key in ignored personal build config. Pairing imports into iPhone Keychain. Possession of both personal app and board permits recovery; this is not hardware-backed protection.
- Reuse SidePulse retained certificate and shared signing lock; create only this app's profiles. Personal release script publishes and reads back en-US/zh-Hans notes.
- Verify board identity before flashing and exact build testing notes after upload.

## Next
1. Get a log export after a finished run on 1.0.12: check "return to app:" lines (which method, if any), "decision:" lines (fast-path hit rate, latency) and tap accuracy across consecutive runs.
1. On phone with 1.0.7: allow Local Network, check debug log for "video: Wi-Fi link up", run tasks; if the link drops while the agent is in other apps (app suspended), consider keeping it alive or accept BLE fallback.
1. Verify accurate calibration with Snap to Item off, fresh Home frames and real phone actions on 1.0.6 (6) after recalibrating.
2. If still failing, inspect startup video metrics; keep board transport and iOS background decoding evidence separate. Do not claim the agent works from a successful upload or Mac BLE benchmark.

## Gotchas
- Release: on the mini write "VERSION BUILD" to ~/Developer/esp32-iphone-agent/release.next, then `open ~/Developer/esp32-iphone-agent/release.command` (GUI session for the keychain); it logs to release-VERSION.log and closes its own Terminal window. Always clean up Terminal windows/temp files on the mini afterwards.
- Host firmware tests: make -C hardware/tests (stroke walker, GOP, bplist).
- Open-loop pointer mapping varies between sessions and by move (probe intercept 0.045 vs -0.004; Search tap landed 0.58 vs 0.50 target) - rely on aim, not calibration alone.
- Cmd+Space opens Search on iPhone; the app passes through .inactive before .active.
- Pointer.drift includes the probe offset (~4.5% x), so it is always > tolerance after touch-probe calibration; never gate runs on `needed`/drift.
- Probe y is noisy for the same move (0.693-0.745 at uy 311); the 1.5% check tap sometimes misses (3.7% seen).
- Board TCP ports 7000/7010/7011/7012/7100 belong to AirPlay (src/airplay/ap_internal.h); the Wi-Fi video server is 7200.
- Build/flash firmware on the MBA from ~/Documents/esp32-iphone-agent (plain copy): rsync hardware/hid_bridge + flash.sh from the mini repo first; arduino-cli is only on the MBA. Board USB port /dev/cu.usbmodem68EE8F5032FC2.
- Internal testers must be added through Apple's web interface; an external betaTester record with the same email cannot be assigned. Future releases reuse the existing internal member.
- Run deploy-personal.py from a Terminal .command opened in the mini GUI session; over plain SSH the login keychain is locked (security exit 36). Simulator 825CA8B2 is gone; tests use iPhone 17 572A4F80.
- Resume an uploaded release with .testflight/deploy-personal.py VERSION BUILD --finalize-only.
- Phone requires cellular data while connected to the board hotspot.
- Initial Bluetooth, screen mirroring, and AssistiveTouch permissions require interaction on the phone.
- USB CDC input buffer is 256 bytes; provisioning script sends 64-byte chunks. Never log decrypted keys.

## Log
- 2026-10-23: logs 7: taps off up to 12% (axis-coupled firmware stepping + shifted start corner), aim unreliable, drawing distorted by per-point BLE timing, return failed. Fixed in firmware (stroke walker + path) and app (2554306); 99/99 iOS + host tests; released 1.0.15 (15) build d512ee20-b299-4266-b333-a62498cb7d37, notes verified; board flashed. Mini release windows cleaned up; release.command self-closes.
- 2026-10-23: logs 6: missed taps = open-loop error up to 8% after good calibration; return-to-app worked but check misread .inactive. Fixed (d42b7bd), 96/96 tests, released 1.0.14 (14) build bd033083-5a81-4c03-8d42-e17a4c699afb, notes verified.
- 2026-10-23: logs 5: 1.0.12 recalibrated before every run (drift gate) and video stalled after Wi-Fi switch (drops 131072). Fixed (6dccf5f), 96/96 tests, released 1.0.13 (13) build 6d70ffa9-6474-4072-b61e-b6c768234cd5, notes verified.
- 2026-10-23: Released 1.0.10 (fast path, 8f36b23), 1.0.11 (Live Activity clearing + return fallback, 6ad1955), 1.0.12 (re-home per run + drift recalibration, 2bad6ad); 95/95 tests, notes verified each.
- 2026-10-23: Released 1.0.9 (9) return-to-app (558f758), build 2906badf-3e4e-43cb-9697-8773f8d3cd94, notes verified. Decisions API latency probe done.
- 2026-10-23: logs 4: Wi-Fi video works; missed taps from failed auto-calibration (residual gate) -> manual fallback. Fixed (e6114a2), 91/91 tests, released 1.0.8 (8) build d3eb5b75-86d5-4e05-acc2-3699495f96e9, notes verified.
- 2026-10-23: Wi-Fi video server on 7100 stole the AirPlay mirror port (mirroring active, no video). Moved to 7200 (5977709), reflashed + verified on MBA; app unchanged.
- 2026-10-23: Wi-Fi video path (0c6ff51): firmware TCP server + app VideoSocket, 90/90 tests. Released 1.0.7 (7), build 5716d9fa-cba3-4420-a6d3-8ffe096eea2d, notes verified. Firmware flashed and verified on MBA.
- 2026-10-23: Phone log analysis: calibration check skew = edge-clamped probe tap kept in pointer correction (x 113 vs 90 units); video failures = BLE backlog after AirPlay bursts outlasting the 15 s wait. Fixed both (0db4434), 89/89 tests, new tests fail on old code. Released 1.0.6 (6), build aadbaff0-37e3-45b0-94c2-193b38e336e4, notes verified.
- 2026-10-23: Ported upstream 6dec6a6 (MetricKit launch crash) and 133ead5 (flash port). 87/87 tests pass. Released 1.0.5 (5), build 3caf4c63-bff6-45ab-99d5-5329e5b154e3, IN_BETA_TESTING; notes verified. Other upstream commits (docs, NOTICE, fastlane) not taken.
- 2026-10-16: Released 1.0.4 (4), build 5e119d9b-c724-407f-8ca9-f598fffd02b3, IN_BETA_TESTING. Personal Testing membership and exact en-US/zh-Hans notes verified. All 87 tests pass; physical iOS 27.2 beta validation pending.
- 2026-10-16: 1.0.3 (3) IN_BETA_TESTING and en-US/zh-Hans notes verified; receipt saved. Replacement 1.0.4 (4) upload accepted, awaiting Apple processing.
- 2026-10-16: Replacement 1.0.4 (4), commit 575f6d0, passes all 87 tests. Release pipeline started; no further firmware changes needed.
- 2026-10-16: Final lifecycle review found explicit stream stops after calibration and task completion would replay history on next warmup. Removed these in streaming mode; preparing replacement 1.0.4 (4), tests running.
- 2026-10-16: Apple accepted 1.0.3 (3). On-board BLE tests pass at 200 kbps idle and 195 kbps with 0.5 s heartbeat traffic, zero gaps, 54–145 ms replies. SSH Bluetooth is denied; launch diagnostics as a Terminal .command via open on MBA.
