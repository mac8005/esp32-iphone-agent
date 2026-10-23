// Mirrored H.264 from AirPlay to BLE, see video_link.h.
#include "video_link.h"
#include <WiFi.h>
#include <esp_heap_caps.h>
#include <esp_random.h>
#include "ble_link.h"
#include "src/video/gop.h"

// GOP since the latest IDR; overflow drops it until the next IDR. A still screen gets an IDR only every
// few minutes, so room for ~27 min of AUs at 5 fps (P-frames of a still screen are tiny).
const size_t GOP_CAP = 4 * 1024 * 1024;
const int MAX_AUS = 8192;
const size_t SCRATCH_CAP = 512 * 1024;   // largest access unit we forward
const size_t MAX_CHUNK = 512;
const uint16_t TCP_PORT = 7100;
const size_t TCP_CHUNK = 1400;  // payload per chunk on the Wi-Fi path

struct Req {
  char id[16];
  uint32_t kb;
  bool bench;
};

static gop_buf gop;
static SemaphoreHandle_t lock;
static uint8_t *scratch;
static QueueHandle_t reqs;
static TaskHandle_t task;
static volatile bool streaming;
static uint16_t seq;
// [len u16 LE] + one chunk: the length prefix frames chunks on the Wi-Fi path, BLE sends from `chunk`.
static uint8_t frame[2 + VCHUNK_HDR + TCP_CHUNK];
static uint8_t *const chunk = frame + 2;

// Wi-Fi video path: the phone is on the board's hotspot for AirPlay anyway, and TCP there is ~20-50x
// faster than BLE notifies. One client, admitted by the per-boot token the app reads over (bonded) BLE
// with `vlink`. While it is up, video goes there instead of BLE; BLE stays the fallback.
static WiFiServer server(TCP_PORT);
static WiFiClient client;
static bool tcpUp;
static String hello;
static uint32_t helloAt;
static char token[17];
static uint32_t sink;  // bumps whenever video moves between BLE and Wi-Fi: the new path needs config + IDR

static void dropClient() {
  if (tcpUp) sink++;
  client.stop();
  tcpUp = false;
}

// Accept a client and check its first line against the token (2 s to send it).
static void tcpPoll() {
  if (client && !client.connected()) dropClient();
  if (WiFiClient c = server.accept()) {
    dropClient();
    client = c;
    client.setNoDelay(true);
    hello = "";
    helloAt = millis();
  }
  if (!client || tcpUp) return;
  while (client.available()) {
    char ch = client.read();
    if (ch == '\n') {
      if (hello == token) {
        tcpUp = true;
        sink++;
      } else {
        dropClient();
      }
      return;
    }
    if (hello.length() < sizeof token) hello += ch;
  }
  if (millis() - helloAt > 2000) dropClient();
}

static size_t videoRoom() { return tcpUp ? TCP_CHUNK : min(ble_video_room(), MAX_CHUNK); }

// Sends `chunk` (len bytes); a failed Wi-Fi write drops the client, so the next AU goes over BLE.
static bool videoSend(size_t len) {
  if (!tcpUp) return ble_video_send(chunk, len);
  frame[0] = (uint8_t)len;
  frame[1] = (uint8_t)(len >> 8);
  if (client.write(frame, len + 2) == len + 2) return true;
  dropClient();
  return false;
}
static uint32_t winStart, winBytes, winFrames, lastIdr;
static volatile uint32_t statKbps, statIdrMs, statAt;
static volatile float statFps;

// One access unit as notifies. A failed chunk still consumes its seq, so the app sees a gap.
static bool sendAu(const uint8_t *p, size_t n, uint8_t flags, uint32_t ts) {
  size_t room = videoRoom();
  if (room < 5) return false;
  vchunk c;
  vchunk_begin(&c, p, n, flags, ts);
  for (size_t len; (len = vchunk_next(&c, chunk, room, seq)) > 0;) {
    bool ok = videoSend(len);
    seq++;
    if (!ok) return false;
  }
  return true;
}

// Copies AU i of generation gen into scratch; false if the GOP moved on.
static bool copyAu(uint32_t gen, int i, gop_au *au) {
  xSemaphoreTake(lock, portMAX_DELAY);
  bool ok = gop.gen == gen && i < gop.n && gop.aus[i].len <= SCRATCH_CAP;
  if (ok) {
    *au = gop.aus[i];
    memcpy(scratch, gop.arena + au->off, au->len);
  }
  xSemaphoreGive(lock);
  return ok;
}

// Snapshot of the GOP state: generation, AU count, SPS/PPS.
static bool snapshot(uint32_t *gen, int *n, uint8_t *cfg, size_t *cfg_len, uint32_t *cfg_ts) {
  xSemaphoreTake(lock, portMAX_DELAY);
  *gen = gop.gen;
  *n = gop.wait_idr ? 0 : gop.n;
  *cfg_len = gop.cfg_len;
  *cfg_ts = gop.cfg_ts;
  memcpy(cfg, gop.cfg, gop.cfg_len);
  xSemaphoreGive(lock);
  return *n > 0 && *cfg_len > 0;
}

static String doSnap() {
  static uint8_t cfg[GOP_CFG_MAX];
  if (!videoRoom()) return "err video not subscribed";
  for (int attempt = 0; attempt < 3; attempt++) {
    uint32_t gen, cfg_ts;
    size_t cfg_len;
    int n;
    if (!snapshot(&gen, &n, cfg, &cfg_len, &cfg_ts)) return "err no video (start screen mirroring)";
    if (!sendAu(cfg, cfg_len, VF_CONFIG | VF_SNAP, cfg_ts)) return "err video send failed";
    bool complete = true;
    for (int i = 0; i < n && complete; i++) {
      gop_au au;
      complete = copyAu(gen, i, &au);
      if (complete && !sendAu(scratch, au.len, VF_SNAP | (au.idr ? VF_IDR : 0), au.ts)) return "err video send failed";
    }
    if (complete) return "ok";  // else a new IDR replaced the GOP mid-send: start over with it
  }
  return "err video changing too fast";
}

static String doBench(uint32_t kb) {
  size_t room = min(ble_video_room(), MAX_CHUNK);
  if (!room) return "err video not subscribed";
  uint32_t start = millis();
  memset(chunk + VCHUNK_HDR, 0xA5, room);
  for (size_t left = kb * 1024; left;) {
    size_t n = min(left, room);
    chunk[0] = (uint8_t)seq;
    chunk[1] = (uint8_t)(seq >> 8);
    chunk[2] = VF_BENCH;
    bool ok = ble_video_send(chunk, VCHUNK_HDR + n);
    seq++;
    if (!ok) return "err ble send failed";
    left -= n;
  }
  return "ok " + String(millis() - start);
}

// Continuous mode: send every AU once, catching up from the GOP's IDR when streaming starts (P-frames
// can't be skipped: each needs the one before, and the next IDR may be minutes away). After a failed
// send, or when video moves between BLE and Wi-Fi, start over from the GOP's IDR.
static void streamStep() {
  static uint32_t txGen = UINT32_MAX, txSink;
  static int next;
  static uint8_t cfg[GOP_CFG_MAX];
  if (!streaming || !videoRoom()) {
    txGen = UINT32_MAX;  // resend config + whole GOP when streaming resumes
    return;
  }
  uint32_t gen, cfg_ts;
  size_t cfg_len;
  int n;
  if (!snapshot(&gen, &n, cfg, &cfg_len, &cfg_ts)) return;
  if (gen != txGen || sink != txSink) {
    txGen = gen;
    txSink = sink;
    next = 0;
    if (!sendAu(cfg, cfg_len, VF_CONFIG, cfg_ts)) { txGen = UINT32_MAX; return; }
  }
  for (gop_au au; next < n && copyAu(gen, next, &au); next++)
    if (!sendAu(scratch, au.len, au.idr ? VF_IDR : 0, au.ts)) { txGen = UINT32_MAX; return; }
}

static void videoTask(void *) {
  for (;;) {
    Req r;
    if (xQueueReceive(reqs, &r, 0) == pdTRUE) {
      String reply = String(r.id) + " " + (r.bench ? doBench(r.kb) : doSnap());
#if DEBUG_SERIAL
      Serial.println("video: " + reply);  // the reply only goes over BLE; mirror it for serial-driven tests
#endif
      ble_reply(reply);
    }
    tcpPoll();
    streamStep();
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(20));
  }
}

bool video_begin() {
  uint8_t *arena = (uint8_t *)heap_caps_malloc(GOP_CAP, MALLOC_CAP_SPIRAM);
  gop_au *aus = (gop_au *)heap_caps_malloc(MAX_AUS * sizeof(gop_au), MALLOC_CAP_SPIRAM);
  scratch = (uint8_t *)heap_caps_malloc(SCRATCH_CAP, MALLOC_CAP_SPIRAM);
  if (!arena || !aus || !scratch) return false;
  gop_init(&gop, arena, GOP_CAP, aus, MAX_AUS);
  lock = xSemaphoreCreateMutex();
  reqs = xQueueCreate(4, sizeof(Req));
  snprintf(token, sizeof token, "%08lx%08lx", (unsigned long)esp_random(), (unsigned long)esp_random());
  server.begin();
  return xTaskCreatePinnedToCore(videoTask, "video", 6 * 1024, NULL, 2, &task, 1) == pdPASS;
}

void video_on_config(const uint8_t *sps_pps, size_t len) {
  xSemaphoreTake(lock, portMAX_DELAY);
  gop_set_config(&gop, sps_pps, len, millis());
  xSemaphoreGive(lock);
}

void video_on_au(const uint8_t *au, size_t len, bool idr) {
  uint32_t now = millis();
  winBytes += len;
  winFrames++;
  if (idr) {
    if (lastIdr) statIdrMs = now - lastIdr;
    lastIdr = now;
  }
  if (now - winStart >= 1000) {
    statKbps = winBytes * 8 / (now - winStart);
    statFps = winFrames * 1000.0f / (now - winStart);
    statAt = now;
    winBytes = winFrames = 0;
    winStart = now;
  }
  xSemaphoreTake(lock, portMAX_DELAY);
  gop_push(&gop, au, len, idr, now);
  xSemaphoreGive(lock);
  xTaskNotifyGive(task);
}

void video_stream(bool on) { streaming = on; }

String video_wifi_link() { return String(TCP_PORT) + " " + token; }

static void request(const String &id, bool bench, uint32_t kb) {
  Req r = {{0}, kb, bench};
  strncpy(r.id, id.c_str(), sizeof r.id - 1);
  if (xQueueSend(reqs, &r, 0) != pdTRUE) ble_reply(id + " err busy");
}

void video_snap(const String &id) { request(id, false, 0); }
void video_bench(const String &id, uint32_t kb) { request(id, true, kb); }

VideoStats video_stats() {
  bool fresh = millis() - statAt < 3000;  // mirroring stopped: report zeros, not stale numbers
  xSemaphoreTake(lock, portMAX_DELAY);
  uint32_t gopBytes = gop.used;
  xSemaphoreGive(lock);
  return {fresh ? statKbps : 0, statIdrMs, gopBytes, fresh ? statFps : 0};
}
