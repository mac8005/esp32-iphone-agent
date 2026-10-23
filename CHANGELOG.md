# Changelog

## 1.0.11 (11) — 2026-10-23

- Finished Live Activities are removed when the app is opened or a new run starts, and on their own after 1 minute instead of 15. Leftovers from earlier launches are cleared too.
- Returning to the app after a run: if Cmd+Space does not open Search on iPhone, the board goes Home and pulls down to open Search, then types the app name. Each attempt is logged ("return to app: …").
- No firmware change.

## 1.0.10 (10) — 2026-10-23

- Fast decisions: on-device text recognition lists the tappable texts on screen, and OpenAI's Decisions API (gpt-6-luna, same API key) picks the next tap. When it is at least 80% sure, the step takes about 1 s instead of 3–5 s.
- Anything else (typing, swiping, unlabelled icons, uncertain choices) still goes to the configured model. On any Decisions API error, the run continues with the model only.
- Only with the OpenAI endpoint (api.openai.com). No firmware change.

## 1.0.9 (9) — 2026-10-23

- When a run ends while another app is in front, the board opens Spotlight (Cmd+Space), types "ESP32 Agent" and presses Return to bring the app back. iOS does not let an app bring itself to the front.
- No firmware change.

## 1.0.8 (8) — 2026-10-23

- Automatic calibration no longer falls back to the one-point manual tap when the probe fit is slightly noisy; the check tap (within 1.5%) decides. The manual fallback cannot correct the pointer's offset (measured 4.5% horizontally), which made taps miss.
- Retry the Wi-Fi video link after 5 s instead of 30 s, so runs start on the fast path.
- No firmware change (Wi-Fi video firmware from 1.0.7 required for the fast path).

## 1.0.7 (7) — 2026-10-23

- Receive the mirrored screen over the board's Wi-Fi hotspot instead of Bluetooth when the board supports it: about 20–50x more bandwidth, so runs start and react after screen transitions within seconds instead of 20–40 s.
- Bluetooth remains the automatic fallback (older firmware, Local Network access denied, Wi-Fi link lost).
- Asks once for Local Network access.
- Companion firmware: TCP video server on the hotspot (port 7200, per-boot token read over the bonded Bluetooth link) and `vlink` command.
- End-to-end operation on iOS 27.2 beta remains unverified.

## 1.0.6 (6) — 2026-10-23

- Fix calibration always failing at the final check point: a probe tap stuck at the screen edge skewed the horizontal correction by about 12%.
- Wait for delayed mirrored video to catch up (up to 90 s while newer frames keep arriving) instead of failing after 15 s; still never acts on an out-of-date screen.
- Runs may take longer to begin after a screen transition, because the board's Bluetooth link (about 110–230 kbps) drains AirPlay bursts in order.
- No firmware change. End-to-end operation on iOS 27.2 beta remains unverified.

## 1.0.5 (5) — 2026-10-23

- Fix a launch crash when iOS delivers a crash or hang diagnostic to the app, which could repeat on every launch (upstream 6dec6a6).
- Firmware flashing script keeps an explicitly given port and follows only the board that re-enumerated after reset (upstream 133ead5). No firmware change; reflashing is not needed.
- Carries forward the 1.0.4 video and calibration fixes. End-to-end operation on iOS 27.2 beta remains unverified.

## 1.0.4 (4) — 2026-10-16

- Carries forward the 1.0.3 calibration and video warmup fixes below.
- Keep live video running after calibration and task completion so the next task does not replay the buffered history again.
- End-to-end operation on iOS 27.2 beta remains unverified.

## 1.0.3 (3) — 2026-10-16

- Begin receiving mirrored video during setup so task startup does not first transfer a long backlog.
- Keep video diagnostics active during startup and while mirroring.
- Reject inaccurate calibration checks and previously saved failed calibrations; a missing check click is no longer a success.
- Companion firmware: keep heartbeat and debug messages from throttling video as if gestures were active.
- End-to-end operation on iOS 27.2 beta remains unverified.

## 1.0.2 (2) — 2026-10-16

- Prevent startup from requesting a long buffered snapshot while live video is streaming.
- Reject delayed screen images before asking the model; report a video error instead of continuing on outdated screens.
- Reset video decoding after lost data or reconnection, and wait for a complete keyframe before resuming.
- Physical validation on iOS 27.2 beta remains required.

## 1.0.1 (1) — 2026-10-16

- First personal TestFlight release for XIAO ESP32-S3, preconfigured for GPT-6.1 Sol with low reasoning effort.
- OpenAI GPT-6 vision support with compatible request parameters and reasoning budget for pointer calibration.
- Personal vision setup imports an encrypted credential from the paired board into the iPhone Keychain; the provider key is absent from the app package.

- No computer: the ESP32 is the AirPlay receiver (ported from UxPlay) with its own hotspot, and talks to a new
  iPhone app over BLE. The app is the agent: planner/actor loop, pointer calibration, run replay, Live Activity,
  widgets, Siri and Shortcuts, self-healing when the board, hotspot or mirroring drops.
- Prompts moved to `prompts/`.
- Product name: ESP32 Agent.
- `server/` is legacy and no longer needed.

## v0.1.0

- Computer-side version: UxPlay + Python server + web UI; the ESP32 is a USB HID bridge over Wi-Fi.
