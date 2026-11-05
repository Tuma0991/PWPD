/*
  ═══════════════════════════════════════════════════════════════════════════
  Guardian ESP32 Firmware  v2.0.0   (event-driven, low-power)
  IoT wearable protection device
  ═══════════════════════════════════════════════════════════════════════════

  What it does
    - Detects falls (MPU6050) and SOS button long-presses, and alerts the app
      through Firebase Realtime Database.
    - Tracks location with the GPS only when needed (duty-cycled), checks
      geofences on the device, and uploads only when something happens.
    - Sends a slow heartbeat so the app can tell "OK" from "offline".

  Hardware (unchanged, no extra parts needed)
    - ESP32-S3 SuperMini
    - MPU6050 on I2C   (SDA = GPIO 8, SCL = GPIO 9)
    - GT-U8 / u-blox NEO-M8N GPS on UART2 (GPS TX -> GPIO 5, GPS RX -> GPIO 6)
    - SOS push button on GPIO 4 (active LOW, internal pull-up; 3 s hold to trigger)
    - Status LED on GPIO 2 (active HIGH, through 220 ohm)

  Libraries (Arduino Library Manager)
    - TinyGPSPlus         by Mikal Hart
    - MPU6050             by Electronic Cats
    - ArduinoJson         by Benoit Blanchon (6.x recommended; 7.x compiles
                          with deprecation warnings)
    - (WiFi, HTTPClient, Preferences, BLE come with the ESP32 core)
    The old "Firebase ESP32 Client" library is NOT used any more.

  Board setup (Arduino IDE)
    Board "ESP32S3 Dev Module", esp32 core 3.x
    USB CDC On Boot: Enabled | Flash Mode: QIO 80MHz | Upload Speed: 921600

  Before you build
    1. Put secrets.h (template provided) in the same folder as this file.
    2. Fill in your Firebase settings there. Never commit secrets.h.

  See CHANGES.md for the full list of changes, tuning and the data model.
  ═══════════════════════════════════════════════════════════════════════════
*/

#include <WiFi.h>
#include <WiFiMulti.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <TinyGPS++.h>
#include <Wire.h>
#include <MPU6050.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLEAdvertising.h>
#include "esp_mac.h"

#include "secrets.h"

#define FW_VERSION   "2.0.0"
#define LOG_ENABLED  1          // set to 0 for production builds (no serial logging)

#if LOG_ENABLED
  #define LOG(...) Serial.printf(__VA_ARGS__)
#else
  #define LOG(...) do {} while (0)
#endif

// Authentication mode is chosen by what secrets.h defines.
#if defined(FIREBASE_API_KEY)
  #define AUTH_EMAIL_MODE 1     // per-device email/password sign-in (recommended)
#else
  #define AUTH_EMAIL_MODE 0     // legacy database secret
#endif

#ifndef PROVISIONING_PIN
  #define PROVISIONING_PIN ""   // empty = no PIN required over BLE
#endif


// ═══════════════════════════════════════════════════════════════════════════
//  1. CONFIGURATION  (every tunable value lives here)
// ═══════════════════════════════════════════════════════════════════════════

// ── Pins ────────────────────────────────────────────────────────────────────
constexpr uint8_t PIN_GPS_RX = 5;      // GPS TX -> ESP32 RX
constexpr uint8_t PIN_GPS_TX = 6;      // GPS RX <- ESP32 TX (used for UBX commands)
constexpr uint8_t PIN_SOS    = 4;
constexpr uint8_t PIN_LED    = 3;
constexpr uint8_t PIN_SDA    = 9;
constexpr uint8_t PIN_SCL    = 8;

// ── CPU frequency (MHz) ─────────────────────────────────────────────────────
constexpr uint32_t CPU_MHZ_IDLE = 80;  // normal running
constexpr uint32_t CPU_MHZ_NET  = 160; // boosted only while talking to Firebase / BLE

// ── IMU sampling and fall detection ─────────────────────────────────────────
constexpr uint32_t IMU_SAMPLE_MS         = 10;      // 100 Hz
constexpr float    ACCEL_LSB_PER_G       = 4096.0f; // +/-8 g range
constexpr bool     IMU_GYRO_STANDBY      = true;    // gyro is unused: put it to sleep (saves ~3 mA)

constexpr float    FREEFALL_G            = 0.4f;    // below this = free-fall
constexpr uint8_t  FREEFALL_MIN_SAMPLES  = 5;       // 50 ms of free-fall
constexpr uint32_t FREEFALL_TO_IMPACT_MS = 800;     // impact must follow free-fall within this
constexpr float    IMPACT_G              = 2.5f;    // impact after free-fall
constexpr float    IMPACT_STRONG_G       = 3.5f;    // impact that counts even without free-fall

constexpr uint32_t POST_IMPACT_SETTLE_MS = 500;     // ignore the bounce right after impact
constexpr uint32_t POST_IMPACT_WINDOW_MS = 2000;    // then look at what the wearer does
constexpr float    POST_ACTIVE_G         = 0.30f;   // deviation from 1 g that counts as "moving"
constexpr float    POST_ACTIVE_FRACTION  = 0.70f;   // above this share = clearly up and moving -> not a fall

constexpr uint32_t FALL_COOLDOWN_MS      = 5000;
constexpr uint32_t SOS_FALL_SUPPRESS_MS  = 3000;    // button jolt must not look like a fall
constexpr uint32_t FALL_CANCEL_WINDOW_MS = 15000;   // "I'm OK" window before a fall alert is sent
constexpr uint32_t CANCEL_HOLD_MS        = 2000;    // hold the button this long to cancel

// ── Button ──────────────────────────────────────────────────────────────────
constexpr uint32_t BUTTON_DEBOUNCE_MS    = 50;
constexpr uint32_t BUTTON_RELEASE_MS     = 30;
constexpr uint32_t SOS_HOLD_MS           = 3000;    // hold the button this long to trigger SOS
constexpr uint32_t BOOT_HOLD_MS          = 5000;    // hold at power-up to re-enter provisioning

// ── Power modes ─────────────────────────────────────────────────────────────
constexpr float    MOTION_DEVIATION_G    = 0.12f;   // deviation from 1 g that counts as motion
constexpr uint32_t REST_AFTER_MS         = 120000;  // no motion for this long -> RESTING

// ── GPS duty cycle ──────────────────────────────────────────────────────────
constexpr bool     GPS_DUTY_CYCLE        = false;   // false = GPS always on (old behaviour)
constexpr bool     DEMO_LIVE_TRACKING    = true;    // DEMO: stream GPS continuously (skip session/duty gating) so the app can pinpoint the device in real time
constexpr uint32_t GPS_ACTIVE_INTERVAL_MS   = 60000;   // ACTIVE and geofences configured
constexpr uint32_t GPS_ACTIVE_NOFENCE_MS    = 300000;  // ACTIVE and no geofences
constexpr uint32_t GPS_RESTING_INTERVAL_MS  = 900000;  // RESTING (15 min)
constexpr uint32_t GPS_EMERGENCY_SLOW_MS    = 30000;   // emergency after the fast phase
constexpr uint32_t GPS_FIX_TIMEOUT_MS       = 90000;   // give up a session after this
constexpr uint32_t GPS_FAIL_BACKOFF_MAX_MS  = 1200000; // 20 min cap when indoors / no sky
constexpr uint32_t GPS_SETTLE_MS            = 3000;    // keep tracking this long after the first fix
constexpr uint32_t GPS_FIX_MAX_AGE_MS       = 1500;
constexpr uint8_t  GPS_MIN_SATS             = 4;
constexpr uint32_t GPS_HOLD_ACCEPT_MS       = 2000;    // continuous mode: refresh stored fix every 2 s
constexpr uint32_t LOCATION_REPORT_MIN_MOVE_M = 25;    // upload a new position only if moved this far

// ── Geofence ────────────────────────────────────────────────────────────────
constexpr int      MAX_GEOFENCES         = 10;
constexpr int      MAX_VERTICES          = 20;
constexpr uint8_t  GEOFENCE_CONFIRM_FIXES = 2;      // consecutive fixes needed to log enter/exit
constexpr uint32_t GEOFENCE_CONFIRM_GAP_MS = 5000;  // wait between confirming fixes
constexpr size_t   GEOFENCE_JSON_BUFFER  = 24576;
constexpr uint32_t GEOFENCE_REFRESH_MS   = 600000;  // re-download geofences every 10 min
constexpr int      GEO_QUEUE_LEN         = 8;

// ── Network timing ──────────────────────────────────────────────────────────
constexpr uint32_t HEARTBEAT_ACTIVE_MS   = 30000;   // 30 s
constexpr uint32_t HEARTBEAT_RESTING_MS  = 60000;   // 60 s
constexpr bool     ENABLE_COMMAND_POLL   = true;    // "locate now" / "refresh geofences" from the app
constexpr uint32_t COMMAND_POLL_ACTIVE_MS  = 30000;
constexpr uint32_t COMMAND_POLL_RESTING_MS = 60000;

constexpr uint32_t EMERGENCY_FAST_PHASE_MS = 600000; // first 10 min of an emergency run at full rate
constexpr uint32_t EMG_POLL_FAST_MS      = 4000;    // check "cleared from app"
constexpr uint32_t EMG_POLL_SLOW_MS      = 20000;
constexpr uint32_t EMG_LOC_FAST_MS       = 10000;   // location update while emergency active
constexpr uint32_t EMG_LOC_SLOW_MS       = 60000;
constexpr uint32_t ALERT_RETRY_MS        = 1500;

constexpr uint32_t WIFI_CONNECT_TIMEOUT_MS = 8000;
constexpr uint32_t WIFI_RETRY_MIN_MS     = 5000;
constexpr uint32_t WIFI_RETRY_MAX_MS     = 300000;
constexpr uint32_t WIFI_RETRY_EMERGENCY_MS = 3000;
constexpr uint32_t FRESH_WIFI_TIMEOUT_MS = 25000;   // first connect after provisioning

constexpr uint32_t NET_BACKOFF_MIN_MS    = 2000;
constexpr uint32_t NET_BACKOFF_MAX_MS    = 300000;
constexpr uint32_t NET_STALL_RESTART_MS  = 3600000; // WiFi up but nothing delivered for 1 h -> reboot

// ── BLE provisioning ────────────────────────────────────────────────────────
#define SERVICE_UUID            "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_UUID_DEVICE_INFO   "4fafc202-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_UUID_WIFI_CREDS    "4fafc203-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_UUID_PROV_STATUS   "4fafc204-1fb5-459e-8fcc-c5c9c331914b"
constexpr uint32_t PROV_WINDOW_MS        = 300000;  // BLE stays on for 5 min, then switches off

// ── Storage (NVS) ───────────────────────────────────────────────────────────
#define NVS_NAMESPACE        "guardian"
#define NVS_KEY_DEVICE_ID    "device_id"
#define NVS_KEY_NET_COUNT    "wifi_n"
#define NVS_KEY_FRESH        "fresh"
#define NVS_KEY_LEGACY_SSID  "wifi_ssid"   // v1.x keys, migrated automatically
#define NVS_KEY_LEGACY_PASS  "wifi_pass"
constexpr int MAX_WIFI_NETS = 3;


// ═══════════════════════════════════════════════════════════════════════════
//  2. TYPES
// ═══════════════════════════════════════════════════════════════════════════

enum Mode : uint8_t { MODE_RESTING = 0, MODE_ACTIVE = 1, MODE_EMERGENCY = 2 };

enum LedPattern : uint8_t {
  LED_OFF, LED_HEARTBEAT, LED_OFFLINE, LED_PROVISIONING,
  LED_FALL_WINDOW, LED_ALERT_SENDING, LED_ALERT_SENT, LED_ACK,
  LED_SOS_HOLD
};

struct GeofenceVertex { double lat; double lng; };

struct Geofence {
  char   id[32];
  char   name[64];
  GeofenceVertex vertices[MAX_VERTICES];
  int    vertexCount;
  double centerLat;
  double centerLng;
  bool   initialized;      // first fix sets the state silently
  bool   inside;           // confirmed state
  uint8_t mismatchCount;   // consecutive fixes that disagree with the confirmed state
};

struct GeoEvent {
  char   id[32];
  char   name[64];
  bool   entered;
  double lat;
  double lng;
  float  distance;
  uint32_t utc;
};

struct GpsFix {
  bool     valid;
  double   lat;
  double   lng;
  uint32_t utc;      // GPS time at the fix (0 = unknown)
  uint32_t atMs;     // millis() when the fix was taken
  uint32_t seq;      // increments on every accepted fix
};

struct WifiNetwork { char ssid[33]; char pass[65]; };


// ═══════════════════════════════════════════════════════════════════════════
//  3. GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════

// ── Objects ─────────────────────────────────────────────────────────────────
TinyGPSPlus    gps;
MPU6050        mpu;
HardwareSerial gpsSerial(2);
Preferences    prefs;
WiFiMulti      wifiMulti;
WiFiClientSecure netClient;
HTTPClient     http;

// ── Identity / config ───────────────────────────────────────────────────────
static String deviceId;
static String devBase;            // "/devices/<id>"
static String shortName;
static String macHex;
static WifiNetwork nets[MAX_WIFI_NETS];
static int netCount = 0;
static bool normalOperation = false;

// ── Emergency state (shared between the sensing loop and the network task) ──
static volatile bool     emergencyActive       = false;
static volatile bool     alertPending          = false;  // alert not yet delivered
static volatile bool     alertDelivered        = false;
static volatile bool     emergencyClearRequest = false;  // set by net task when the app clears it
static volatile bool     fallFlag              = false;
static volatile bool     fallPending           = false;  // inside the cancel window
static volatile uint32_t emergencyStartMs      = 0;
static char              alertReason[48]       = "";
static portMUX_TYPE      alertMux              = portMUX_INITIALIZER_UNLOCKED;

// ── Mode / connectivity flags ───────────────────────────────────────────────
static volatile uint8_t  currentMode           = MODE_ACTIVE;
static volatile bool     wifiUp                = false;
static volatile bool     locateRequested       = false;
static volatile bool     locationReportPending = false;
static volatile bool     geofenceRefreshRequested = false;
static volatile bool     imuOk                 = false;
static volatile float    lastAx = 0, lastAy = 0, lastAz = 1;

// ── GPS state ───────────────────────────────────────────────────────────────
static GpsFix       lastFix = {false, 0, 0, 0, 0, 0};
static portMUX_TYPE fixMux  = portMUX_INITIALIZER_UNLOCKED;
static bool     gpsPowered      = true;     // receiver is running at power-up
static bool     gpsDutyOk       = true;     // cleared if the module ignores the stop command
static bool     gpsDutyVerified = false;
static uint32_t gpsStopCheckAt  = 0;
static bool     gpsSession      = false;
static uint32_t gpsSessionStart = 0;
static uint32_t gpsFirstFixAt   = 0;
static uint32_t gpsAcceptAfter  = 0;
static uint32_t gpsNextSession  = 0;
static uint8_t  gpsFailCount    = 0;
static uint32_t gpsRxWindow     = 0;        // bytes received since the last status line
static uint32_t gpsRxTotal      = 0;        // bytes received since boot
static char     nmeaBuf[96];                 // raw NMEA sentence capture (diagnostic)
static uint8_t  nmeaLen = 0;
static uint32_t lastNmeaDump = 0;
static double   reportedLat = 0, reportedLng = 0;
static bool     reportedValid = false;

// ── Geofences ───────────────────────────────────────────────────────────────
static Geofence geofences[MAX_GEOFENCES];
static Geofence geoScratch[MAX_GEOFENCES];
static volatile int geofenceCount = 0;
static SemaphoreHandle_t geoMutex = nullptr;
static QueueHandle_t     geoQueue = nullptr;

// ── Fall detection / button ─────────────────────────────────────────────────
enum FallPhase : uint8_t { FALL_IDLE, FALL_POST_IMPACT };
static FallPhase fallPhase = FALL_IDLE;
static uint8_t   freeSamples = 0;
static bool      sawFreefall = false;
static uint32_t  lastFreefallAt = 0;
static uint32_t  impactAt = 0;
static uint32_t  postSamples = 0, postActive = 0;
static uint32_t  fallIgnoreUntil = 0;
static uint32_t  fallPendingSince = 0;
static uint32_t  lastMotionMs = 0;
static uint32_t  lastImuSampleMs = 0;
static uint32_t  lastImuRetryMs = 0;
static uint16_t  imuBadSamples = 0;

static volatile bool     sosEdge = false;
static volatile uint32_t sosEdgeAt = 0;
static bool              sosHolding = false;   // button held, waiting for the SOS long-press to complete

// ── LED ─────────────────────────────────────────────────────────────────────
static uint32_t ledAckUntil = 0;

// ── Provisioning ────────────────────────────────────────────────────────────
static bool provisioningActive = false;
static bool provisioningIdle   = false;
static uint32_t provStartMs    = 0;
static volatile bool bleClientConnected = false;
static volatile bool pendingRestart     = false;
static BLECharacteristic* provStatusChar = nullptr;

// ── Network task ────────────────────────────────────────────────────────────
static TaskHandle_t netTaskHandle = nullptr;
static String   authToken;
static uint32_t authExpiryMs = 0;


// ═══════════════════════════════════════════════════════════════════════════
//  4. FORWARD DECLARATIONS
// ═══════════════════════════════════════════════════════════════════════════

static void triggerEmergency(const char* reason, bool fromFall, uint32_t now);
static void ledAck(uint32_t now);
static void gpsEndSession(uint32_t now, bool ok);
static void startProvisioning();
static void netTask(void* arg);


// ═══════════════════════════════════════════════════════════════════════════
//  5. SMALL HELPERS
// ═══════════════════════════════════════════════════════════════════════════

static void cpuBoost() { if (getCpuFrequencyMhz() != CPU_MHZ_NET)  setCpuFrequencyMhz(CPU_MHZ_NET); }
static void cpuRelax() { if (getCpuFrequencyMhz() != CPU_MHZ_IDLE) setCpuFrequencyMhz(CPU_MHZ_IDLE); }

static const char* modeName(uint8_t m) {
  switch (m) {
    case MODE_RESTING:   return "resting";
    case MODE_EMERGENCY: return "emergency";
    default:             return "active";
  }
}

static float distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371000.0;
  double dLat = (lat2 - lat1) * DEG_TO_RAD;
  double dLon = (lon2 - lon1) * DEG_TO_RAD;
  double a = sin(dLat / 2) * sin(dLat / 2) +
             cos(lat1 * DEG_TO_RAD) * cos(lat2 * DEG_TO_RAD) * sin(dLon / 2) * sin(dLon / 2);
  return (float)(R * 2.0 * atan2(sqrt(a), sqrt(1.0 - a)));
}

static GpsFix getFix() {
  portENTER_CRITICAL(&fixMux);
  GpsFix f = lastFix;
  portEXIT_CRITICAL(&fixMux);
  return f;
}

// UTC time of "now", extrapolated from the last fix (0 if never had GPS time).
static uint32_t fixUtcNow(const GpsFix& f) {
  if (!f.valid || f.utc == 0) return 0;
  return f.utc + (millis() - f.atMs) / 1000;
}

// Seconds since 1970 from the GPS date/time (no timezone / libc dependency).
static uint32_t gpsUtcEpoch() {
  if (!gps.date.isValid() || !gps.time.isValid()) return 0;
  int y = gps.date.year(), m = gps.date.month(), d = gps.date.day();
  if (y < 2020) return 0;
  y -= (m <= 2) ? 1 : 0;
  int era = y / 400;
  unsigned yoe = (unsigned)(y - era * 400);
  unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  long days = era * 146097L + (long)doe - 719468L;
  return (uint32_t)(days * 86400L + gps.time.hour() * 3600L +
                    gps.time.minute() * 60L + gps.time.second());
}


// ═══════════════════════════════════════════════════════════════════════════
//  6. STATUS LED  (non-blocking; one function decides what to show)
// ═══════════════════════════════════════════════════════════════════════════
//   heartbeat      : 100 ms blink every 4 s          (all good)
//   offline        : double blink every 4 s          (no WiFi)
//   provisioning   : 100 ms blink every 2 s          (BLE setup mode)
//   fall window    : fast flashing                   (hold button 2 s = "I'm OK")
//   sos hold       : fast flashing                   (keep holding to send SOS)
//   alert sending  : double blink every 1 s          (alert not delivered yet)
//   alert sent     : 150 ms blink every 2 s          (help requested, delivered)
//   acknowledge    : ~4 quick blinks                 (button press received)

static bool ledPatternOn(LedPattern p, uint32_t t) {
  switch (p) {
    case LED_HEARTBEAT:     return (t % 4000) < 100;
    case LED_OFFLINE:       { uint32_t x = t % 4000; return x < 100 || (x >= 250 && x < 350); }
    case LED_PROVISIONING:  return (t % 2000) < 100;
    case LED_FALL_WINDOW:   return (t % 200) < 100;
    case LED_ALERT_SENDING: { uint32_t x = t % 1000; return x < 80 || (x >= 160 && x < 240); }
    case LED_ALERT_SENT:    return (t % 2000) < 150;
    case LED_ACK:           return (t % 200) < 100;
    case LED_SOS_HOLD:      return (t % 200) < 100;
    default:                return false;
  }
}

static LedPattern chooseLedPattern(uint32_t now) {
  if ((int32_t)(ledAckUntil - now) > 0) return LED_ACK;
  if (provisioningActive)               return LED_PROVISIONING;
  if (provisioningIdle)                 return LED_HEARTBEAT;
  if (fallPending)                      return LED_FALL_WINDOW;
  if (sosHolding)                       return LED_SOS_HOLD;
  if (emergencyActive)                  return alertDelivered ? LED_ALERT_SENT : LED_ALERT_SENDING;
  if (!wifiUp)                          return LED_OFFLINE;
  return LED_HEARTBEAT;
}

static void ledUpdate(uint32_t now) {
  static bool last = false;
  bool on = ledPatternOn(chooseLedPattern(now), now);
  if (on != last) {
    digitalWrite(PIN_LED, on ? HIGH : LOW);
    last = on;
  }
}

static void ledAck(uint32_t now) { ledAckUntil = now + 900; }


// ═══════════════════════════════════════════════════════════════════════════
//  7. STORED CONFIGURATION (NVS): device id and up to 3 WiFi networks
// ═══════════════════════════════════════════════════════════════════════════

static void persistNetworks() {
  prefs.begin(NVS_NAMESPACE, false);
  prefs.putUChar(NVS_KEY_NET_COUNT, (uint8_t)netCount);
  char key[8];
  for (int i = 0; i < MAX_WIFI_NETS; i++) {
    snprintf(key, sizeof(key), "s%d", i);
    if (i < netCount) prefs.putString(key, nets[i].ssid); else prefs.remove(key);
    snprintf(key, sizeof(key), "p%d", i);
    if (i < netCount) prefs.putString(key, nets[i].pass); else prefs.remove(key);
  }
  prefs.end();
}

static void loadConfig() {
  prefs.begin(NVS_NAMESPACE, false);

  deviceId = prefs.getString(NVS_KEY_DEVICE_ID, "");
  // Regenerate if missing, or if it was saved from a degenerate all-zero MAC.
  if (deviceId.length() == 0 || deviceId == "guardian_000000000000") {
    deviceId = "guardian_" + macHex;
    prefs.putString(NVS_KEY_DEVICE_ID, deviceId);
  }

  netCount = 0;
  uint8_t n = prefs.getUChar(NVS_KEY_NET_COUNT, 0);
  char key[8];
  for (int i = 0; i < n && i < MAX_WIFI_NETS; i++) {
    snprintf(key, sizeof(key), "s%d", i);
    String s = prefs.getString(key, "");
    snprintf(key, sizeof(key), "p%d", i);
    String p = prefs.getString(key, "");
    if (s.length() == 0) continue;
    strlcpy(nets[netCount].ssid, s.c_str(), sizeof(nets[netCount].ssid));
    strlcpy(nets[netCount].pass, p.c_str(), sizeof(nets[netCount].pass));
    netCount++;
  }

  // Migrate the single network saved by firmware v1.x
  if (netCount == 0) {
    String s = prefs.getString(NVS_KEY_LEGACY_SSID, "");
    if (s.length() > 0) {
      String p = prefs.getString(NVS_KEY_LEGACY_PASS, "");
      strlcpy(nets[0].ssid, s.c_str(), sizeof(nets[0].ssid));
      strlcpy(nets[0].pass, p.c_str(), sizeof(nets[0].pass));
      netCount = 1;
      prefs.remove(NVS_KEY_LEGACY_SSID);
      prefs.remove(NVS_KEY_LEGACY_PASS);
      prefs.end();
      persistNetworks();
      LOG("[CONFIG] Migrated v1 WiFi credentials\n");
      return;
    }
  }
  prefs.end();

  LOG("[CONFIG] Device ID: %s\n", deviceId.c_str());
  LOG("[CONFIG] Saved WiFi networks: %d\n", netCount);
}

// Add a network, or update it if the SSID is already stored. Keeps the newest 3.
static void saveWifiNetwork(const char* ssid, const char* pass) {
  for (int i = 0; i < netCount; i++) {
    if (strcmp(nets[i].ssid, ssid) == 0) {
      strlcpy(nets[i].pass, pass, sizeof(nets[i].pass));
      persistNetworks();
      return;
    }
  }
  if (netCount >= MAX_WIFI_NETS) {
    for (int i = 1; i < MAX_WIFI_NETS; i++) nets[i - 1] = nets[i];
    netCount = MAX_WIFI_NETS - 1;
  }
  strlcpy(nets[netCount].ssid, ssid, sizeof(nets[netCount].ssid));
  strlcpy(nets[netCount].pass, pass, sizeof(nets[netCount].pass));
  netCount++;
  persistNetworks();
}

static void clearWifiNetworks() {
  netCount = 0;
  persistNetworks();
}

static void setFreshFlag(bool v) {
  prefs.begin(NVS_NAMESPACE, false);
  prefs.putBool(NVS_KEY_FRESH, v);
  prefs.end();
}

static bool takeFreshFlag() {
  prefs.begin(NVS_NAMESPACE, false);
  bool v = prefs.getBool(NVS_KEY_FRESH, false);
  if (v) prefs.putBool(NVS_KEY_FRESH, false);
  prefs.end();
  return v;
}

static void registerWifiNetworks() {
  for (int i = 0; i < netCount; i++) {
    wifiMulti.addAP(nets[i].ssid, nets[i].pass[0] ? nets[i].pass : NULL);
  }
}


// ═══════════════════════════════════════════════════════════════════════════
//  8. BLE PROVISIONING  (only on when needed, closes itself after 5 minutes)
// ═══════════════════════════════════════════════════════════════════════════

static String buildDeviceInfoJSON() {
  StaticJsonDocument<256> doc;
  doc["deviceId"]       = deviceId;
  doc["firmware"]       = FW_VERSION;
  doc["wifiConfigured"] = (netCount > 0);
  doc["wifiConnected"]  = (WiFi.status() == WL_CONNECTED);
  String json;
  serializeJson(doc, json);
  return json;
}

static void notifyProvStatus(const char* status, const char* message) {
  if (!provStatusChar) return;
  StaticJsonDocument<192> doc;
  doc["status"]  = status;
  doc["message"] = message;
  String json;
  serializeJson(doc, json);
  provStatusChar->setValue(json.c_str());
  provStatusChar->notify();
}

class ProvServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { bleClientConnected = true; }
  void onDisconnect(BLEServer*) override {
    bleClientConnected = false;
    BLEDevice::startAdvertising();      // stay discoverable if the phone drops mid-setup
  }
};

class DeviceInfoCallback : public BLECharacteristicCallbacks {
  void onRead(BLECharacteristic* c) override {
    String info = buildDeviceInfoJSON();
    c->setValue(info.c_str());
  }
};

class WiFiCredsCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String json = String(c->getValue().c_str());

    StaticJsonDocument<384> doc;
    if (deserializeJson(doc, json)) {
      notifyProvStatus("error", "Invalid JSON");
      return;
    }

    const char* ssid = doc["ssid"] | "";
    const char* pass = doc["password"] | "";     // empty is allowed (open networks)

    if (strlen(ssid) == 0 || strlen(ssid) > 32 || strlen(pass) > 63) {
      notifyProvStatus("error", "Invalid SSID or password length");
      return;
    }
    if (strlen(PROVISIONING_PIN) > 0) {
      const char* pin = doc["pin"] | "";
      if (strcmp(pin, PROVISIONING_PIN) != 0) {
        notifyProvStatus("error", "Invalid PIN");
        return;
      }
    }

    saveWifiNetwork(ssid, pass);
    setFreshFlag(true);
    LOG("[BLE] WiFi network saved: %s\n", ssid);   // password is never logged

    notifyProvStatus("connected", "WiFi credentials saved. Rebooting...");

    // Restart from loop(), not here: killing the connection inside the callback
    // would drop the GATT write acknowledgement (error 133 on the phone).
    pendingRestart = true;
  }
};

static void startProvisioning() {
  LOG("\n=== BLE Provisioning Mode (%lu s window) ===\n", (unsigned long)(PROV_WINDOW_MS / 1000));

  setCpuFrequencyMhz(CPU_MHZ_NET);
  WiFi.disconnect(true);
  WiFi.mode(WIFI_OFF);              // WiFi and BLE share one radio
  delay(100);

  BLEDevice::init(shortName.c_str());
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ProvServerCallbacks());
  BLEService* service = server->createService(SERVICE_UUID);

  BLECharacteristic* infoChar =
      service->createCharacteristic(CHAR_UUID_DEVICE_INFO, BLECharacteristic::PROPERTY_READ);
  infoChar->setCallbacks(new DeviceInfoCallback());
  infoChar->setValue(buildDeviceInfoJSON().c_str());

  provStatusChar = service->createCharacteristic(
      CHAR_UUID_PROV_STATUS, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  provStatusChar->setValue("{\"status\":\"waiting\"}");

  BLECharacteristic* credsChar =
      service->createCharacteristic(CHAR_UUID_WIFI_CREDS, BLECharacteristic::PROPERTY_WRITE);
  credsChar->setCallbacks(new WiFiCredsCallback());

  service->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);

  // flutter_blue_plus only sees names that are in the advertising/scan-response payload
  BLEAdvertisementData scanResp;
  scanResp.setName(shortName.c_str());
  adv->setScanResponseData(scanResp);
  adv->setMinPreferred(0x06);
  adv->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  provisioningActive = true;
  provisioningIdle   = false;
  provStartMs        = millis();
  LOG("Advertising as: %s\n", shortName.c_str());
}

static void stopProvisioning() {
  BLEDevice::deinit(true);
  provStatusChar = nullptr;
  provisioningActive = false;
  setCpuFrequencyMhz(CPU_MHZ_IDLE);
  LOG("[BLE] Provisioning window closed\n");
}

// Runs instead of the normal loop while the device is being set up.
static void provisioningLoop(uint32_t now) {
  if (pendingRestart) {
    delay(500);
    ESP.restart();
  }

  if (provisioningActive) {
    if (!bleClientConnected && (now - provStartMs) > PROV_WINDOW_MS) {
      stopProvisioning();
      if (netCount > 0) {
        ESP.restart();                // retry saved networks in normal mode
      } else {
        provisioningIdle = true;      // wait for a button press to reopen BLE
        LOG("[BLE] No WiFi saved. Press the button to restart setup.\n");
      }
    }
  } else if (provisioningIdle) {
    if (sosEdge || digitalRead(PIN_SOS) == LOW) {
      sosEdge = false;
      provisioningIdle = false;
      startProvisioning();
      delay(300);
    }
  }

  ledUpdate(now);
  delay(20);
}


// ═══════════════════════════════════════════════════════════════════════════
//  9. IMU AND FALL DETECTION
// ═══════════════════════════════════════════════════════════════════════════
//  Pipeline (100 Hz):  free-fall  ->  impact  ->  quick look at what the
//  wearer does  ->  15 s "I'm OK" window  ->  alert.
//  A very hard impact (> IMPACT_STRONG_G) counts even without free-fall, so
//  falls that start without a clear weightless phase are not missed.

static bool imuInit() {
  mpu.initialize();
  if (!mpu.testConnection()) {
    imuOk = false;
    LOG("[IMU] MPU6050 not responding\n");
    return false;
  }
  mpu.setFullScaleAccelRange(MPU6050_ACCEL_FS_8);    // +/-8 g so impacts are not clipped

  if (IMU_GYRO_STANDBY) {
    mpu.setClockSource(MPU6050_CLOCK_INTERNAL);      // gyro PLL would stop with the gyro asleep
    Wire.beginTransmission(0x68);
    Wire.write(0x6C);                                // PWR_MGMT_2
    Wire.write(0x07);                                // STBY_XG | STBY_YG | STBY_ZG
    Wire.endTransmission();
  }

  imuOk = true;
  imuBadSamples = 0;
  LOG("[IMU] MPU6050 ready (+/-8 g%s)\n", IMU_GYRO_STANDBY ? ", gyro standby" : "");
  return true;
}

static void beginFallCancelWindow(uint32_t now) {
  fallPending = true;
  sosHolding = false;           // a fall takes over the button: cancel semantics now apply
  fallPendingSince = now;
  LOG("[FALL] Possible fall. Alert in %lu s (hold button %lu s = cancel)\n",
      (unsigned long)(FALL_CANCEL_WINDOW_MS / 1000), (unsigned long)(CANCEL_HOLD_MS / 1000));
}

static void cancelFall(uint32_t now) {
  fallPending = false;
  fallIgnoreUntil = now + FALL_COOLDOWN_MS;
  ledAck(now);
  LOG("[FALL] Cancelled by wearer\n");
}

static void fallDetectorUpdate(float g, uint32_t now) {
  if (emergencyActive || fallPending) { fallPhase = FALL_IDLE; return; }
  if ((int32_t)(now - fallIgnoreUntil) < 0) return;

  if (fallPhase == FALL_IDLE) {
    if (g < FREEFALL_G) {
      if (freeSamples < 255) freeSamples++;
      if (freeSamples >= FREEFALL_MIN_SAMPLES) { sawFreefall = true; lastFreefallAt = now; }
    } else {
      freeSamples = 0;
    }

    if (g > IMPACT_G) {
      bool afterFreefall = sawFreefall && (now - lastFreefallAt) <= FREEFALL_TO_IMPACT_MS;
      if (afterFreefall || g > IMPACT_STRONG_G) {
        LOG("[FALL] Impact %.2f g (%s)\n", g, afterFreefall ? "after free-fall" : "strong");
        fallPhase = FALL_POST_IMPACT;
        impactAt = now;
        postSamples = 0;
        postActive = 0;
        sawFreefall = false;
        freeSamples = 0;
      }
    }
    return;
  }

  // FALL_POST_IMPACT: judge the wearer's movement after the impact
  uint32_t t = now - impactAt;
  if (t >= POST_IMPACT_SETTLE_MS) {
    postSamples++;
    if (fabsf(g - 1.0f) > POST_ACTIVE_G) postActive++;
  }
  if (t >= POST_IMPACT_SETTLE_MS + POST_IMPACT_WINDOW_MS) {
    fallPhase = FALL_IDLE;
    bool clearlyMoving = postSamples > 0 &&
                         ((float)postActive / (float)postSamples) > POST_ACTIVE_FRACTION;
    if (clearlyMoving) {
      LOG("[FALL] Discarded: wearer is moving normally afterwards\n");
      fallIgnoreUntil = now + 1000;
    } else {
      beginFallCancelWindow(now);
    }
  }
}

static void imuSample(uint32_t now) {
  if (!imuOk) {
    if (now - lastImuRetryMs >= 30000) { lastImuRetryMs = now; imuInit(); }
    return;
  }

  int16_t ax, ay, az;
  mpu.getAcceleration(&ax, &ay, &az);

  // Detect a dead / disconnected sensor (bus reads as all-zero or all-ones)
  if ((ax == 0 && ay == 0 && az == 0) || (ax == -1 && ay == -1 && az == -1)) {
    if (++imuBadSamples >= 50) { imuOk = false; LOG("[IMU] Sensor fault, will retry\n"); }
    return;
  }
  imuBadSamples = 0;

  float x = ax / ACCEL_LSB_PER_G;
  float y = ay / ACCEL_LSB_PER_G;
  float z = az / ACCEL_LSB_PER_G;
  float g = sqrtf(x * x + y * y + z * z);
  lastAx = x; lastAy = y; lastAz = z;

  if (fabsf(g - 1.0f) > MOTION_DEVIATION_G) lastMotionMs = now;
  fallDetectorUpdate(g, now);
}


// ═══════════════════════════════════════════════════════════════════════════
//  10. EMERGENCY CONTROL  (SOS button and confirmed falls)
// ═══════════════════════════════════════════════════════════════════════════

static void triggerEmergency(const char* reason, bool fromFall, uint32_t now) {
  if (emergencyActive) {
    ledAck(now);
    LOG("[EMERGENCY] Already active\n");
    return;
  }

  portENTER_CRITICAL(&alertMux);
  strlcpy(alertReason, reason, sizeof(alertReason));
  fallFlag          = fromFall;
  alertDelivered    = false;
  emergencyStartMs  = now;
  emergencyActive   = true;
  alertPending      = true;
  portEXIT_CRITICAL(&alertMux);

  fallPending = false;
  LOG("\n[EMERGENCY] %s\n", reason);

  if (netTaskHandle) xTaskNotifyGive(netTaskHandle);   // wake the network task now
}

static void onSosPressed(uint32_t now) {
  fallIgnoreUntil = now + SOS_FALL_SUPPRESS_MS;
  LOG("\n>>> SOS BUTTON <<<\n");
  triggerEmergency("SOS button pressed", false, now);
}

// SOS now needs a SOS_HOLD_MS long-press so accidental taps are ignored.
// While a fall window is open the decision waits for the release:
// short press = send now, hold CANCEL_HOLD_MS = "I'm OK".
static void handleButton(uint32_t now) {
  static bool pressActive = false;
  static bool holdHandled = false;
  static uint32_t pressStart = 0;
  static uint32_t lastAccepted = 0;
  static uint32_t releaseSince = 0;

  bool low = (digitalRead(PIN_SOS) == LOW);

  if (!pressActive) {
    if ((sosEdge || low) && (now - lastAccepted) > BUTTON_DEBOUNCE_MS) {
      bool fromEdge = sosEdge;
      sosEdge = false;
      pressActive = true;
      holdHandled = false;
      pressStart = fromEdge ? sosEdgeAt : now;
      lastAccepted = now;
      releaseSince = 0;
      if (!fallPending) {
        sosHolding = true;         // arm the SOS: it fires once the hold completes
        ledAck(now);               // acknowledge the press so the wearer keeps holding
      }
    }
    return;
  }

  if (!low) {
    if (releaseSince == 0) releaseSince = now;
    if ((now - releaseSince) >= BUTTON_RELEASE_MS) {
      pressActive = false;
      sosHolding = false;          // released early: no alert
      if (fallPending && !holdHandled) onSosPressed(now);   // short press during fall window
    }
  } else {
    releaseSince = 0;
    if (fallPending) {
      if (!holdHandled && (now - pressStart) >= CANCEL_HOLD_MS) {
        holdHandled = true;
        sosHolding = false;
        cancelFall(now);
      }
    } else {
      if (!holdHandled && (now - pressStart) >= SOS_HOLD_MS) {
        holdHandled = true;
        sosHolding = false;
        onSosPressed(now);
      }
    }
  }
}

void IRAM_ATTR onSosEdge() {
  sosEdgeAt = millis();
  sosEdge = true;
}


// ═══════════════════════════════════════════════════════════════════════════
//  11. GEOFENCES  (evaluated on the device; uploads only on enter / exit)
// ═══════════════════════════════════════════════════════════════════════════

static bool pointInPolygon(double lat, double lng, const GeofenceVertex* v, int count) {
  if (count < 3) return false;
  bool inside = false;
  for (int i = 0, j = count - 1; i < count; j = i++) {
    if (((v[i].lat > lat) != (v[j].lat > lat)) &&
        (lng < (v[j].lng - v[i].lng) * (lat - v[i].lat) / (v[j].lat - v[i].lat) + v[i].lng)) {
      inside = !inside;
    }
  }
  return inside;
}

static size_t childCount(JsonVariant v) {
  if (v.is<JsonArray>())  return v.as<JsonArray>().size();
  if (v.is<JsonObject>()) return v.as<JsonObject>().size();
  return 0;
}

// Firebase returns an array for 0,1,2.. keys and an object for push-ids; accept both.
static JsonVariant childAt(JsonVariant v, size_t index) {
  if (v.is<JsonArray>()) return v.as<JsonArray>()[index].as<JsonVariant>();
  size_t i = 0;
  for (JsonPair kv : v.as<JsonObject>()) {
    if (i++ == index) return kv.value();
  }
  return JsonVariant();
}

static bool parseGeofences(const String& json, Geofence* out, int& count) {
  DynamicJsonDocument doc(GEOFENCE_JSON_BUFFER);
  if (deserializeJson(doc, json)) return false;

  count = 0;
  JsonVariant root = doc.as<JsonVariant>();
  size_t n = childCount(root);

  for (size_t i = 0; i < n && count < MAX_GEOFENCES; i++) {
    JsonVariant fence = childAt(root, i);
    if (!fence.is<JsonObject>()) continue;

    Geofence& g = out[count];
    memset(&g, 0, sizeof(g));
    strlcpy(g.id,   fence["id"]   | "unknown", sizeof(g.id));
    strlcpy(g.name, fence["name"] | "unnamed", sizeof(g.name));

    JsonVariant verts = fence["vertices"];
    size_t vn = childCount(verts);
    double sumLat = 0, sumLng = 0;
    for (size_t k = 0; k < vn && g.vertexCount < MAX_VERTICES; k++) {
      JsonVariant vv = childAt(verts, k);
      if (!vv.is<JsonObject>()) continue;
      g.vertices[g.vertexCount].lat = vv["lat"] | 0.0;
      g.vertices[g.vertexCount].lng = vv["lng"] | 0.0;
      sumLat += g.vertices[g.vertexCount].lat;
      sumLng += g.vertices[g.vertexCount].lng;
      g.vertexCount++;
    }
    if (g.vertexCount < 3) continue;       // not a usable polygon
    g.centerLat = sumLat / g.vertexCount;
    g.centerLng = sumLng / g.vertexCount;
    count++;
  }
  return true;
}

// Swap in a freshly downloaded list, keeping the inside/outside state of fences
// that still exist so a refresh never creates false enter/exit events.
static void applyGeofences(Geofence* fresh, int count) {
  xSemaphoreTake(geoMutex, portMAX_DELAY);
  for (int i = 0; i < count; i++) {
    for (int j = 0; j < geofenceCount; j++) {
      if (strcmp(fresh[i].id, geofences[j].id) == 0) {
        fresh[i].initialized   = geofences[j].initialized;
        fresh[i].inside        = geofences[j].inside;
        fresh[i].mismatchCount = geofences[j].mismatchCount;
        break;
      }
    }
  }
  memcpy(geofences, fresh, sizeof(Geofence) * (size_t)count);
  geofenceCount = count;
  xSemaphoreGive(geoMutex);
  LOG("[GEOFENCE] %d geofence(s) loaded\n", count);
}

static void queueGeoEvent(const Geofence& g, bool entered, double lat, double lng, uint32_t utc) {
  GeoEvent ev;
  memset(&ev, 0, sizeof(ev));
  strlcpy(ev.id, g.id, sizeof(ev.id));
  strlcpy(ev.name, g.name, sizeof(ev.name));
  ev.entered  = entered;
  ev.lat      = lat;
  ev.lng      = lng;
  ev.distance = distanceMeters(lat, lng, g.centerLat, g.centerLng);
  ev.utc      = utc;

  if (xQueueSend(geoQueue, &ev, 0) != pdTRUE) {      // queue full: drop the oldest
    GeoEvent old;
    xQueueReceive(geoQueue, &old, 0);
    xQueueSend(geoQueue, &ev, 0);
  }
  LOG("[GEOFENCE] '%s' %s\n", g.name, entered ? "entered" : "exited");
  if (netTaskHandle) xTaskNotifyGive(netTaskHandle);
}

// Returns true if some fence has a change that still needs one more confirming fix.
static bool geofenceEvaluate(double lat, double lng, uint32_t utc) {
  bool pending = false;
  xSemaphoreTake(geoMutex, portMAX_DELAY);
  for (int i = 0; i < geofenceCount; i++) {
    Geofence& g = geofences[i];
    bool inside = pointInPolygon(lat, lng, g.vertices, g.vertexCount);

    if (!g.initialized) {                 // first fix: learn the state silently
      g.inside = inside;
      g.initialized = true;
      g.mismatchCount = 0;
      continue;
    }
    if (inside == g.inside) { g.mismatchCount = 0; continue; }

    if (g.mismatchCount < 255) g.mismatchCount++;
    if (g.mismatchCount >= GEOFENCE_CONFIRM_FIXES) {
      g.inside = inside;
      g.mismatchCount = 0;
      queueGeoEvent(g, inside, lat, lng, utc);
    } else {
      pending = true;
    }
  }
  xSemaphoreGive(geoMutex);
  return pending;
}


// ═══════════════════════════════════════════════════════════════════════════
//  12. GPS  (event-driven: the receiver sleeps between short "sessions")
// ═══════════════════════════════════════════════════════════════════════════
//  The receiver is stopped / started with the u-blox UBX-CFG-RST "controlled
//  GNSS stop/start" command, so no extra hardware is needed. After a stop the
//  clock and satellite data are kept, so the next start is a fast hot start.
//
//  A session is started when:  the schedule says so (60 s moving, 15 min
//  resting), the app asks "locate now", or an emergency begins.
//  A session ends as soon as a settled fix has been taken.

static void ubxSend(uint8_t cls, uint8_t id, const uint8_t* payload, uint16_t len) {
  uint8_t ckA = 0, ckB = 0;
  auto put = [&](uint8_t b) { gpsSerial.write(b); ckA += b; ckB += ckA; };
  gpsSerial.write(0xB5);
  gpsSerial.write(0x62);
  put(cls);
  put(id);
  put(len & 0xFF);
  put(len >> 8);
  for (uint16_t i = 0; i < len; i++) put(payload[i]);
  gpsSerial.write(ckA);
  gpsSerial.write(ckB);
}

static void gpsPowerOn() {
  if (gpsPowered) return;
  const uint8_t start[4] = {0x00, 0x00, 0x09, 0x00};   // controlled GNSS start (hot)
  ubxSend(0x06, 0x04, start, 4);
  gpsPowered = true;
}

static void gpsPowerOff(uint32_t now) {
  if (!gpsPowered || !GPS_DUTY_CYCLE || !gpsDutyOk) return;
  const uint8_t stop[4] = {0x00, 0x00, 0x08, 0x00};    // controlled GNSS stop
  ubxSend(0x06, 0x04, stop, 4);
  gpsPowered = false;
  if (!gpsDutyVerified && lastFix.valid) gpsStopCheckAt = now + 5000;
}

static bool gpsFixFresh() {
  // A valid, recent position fix is enough. The GT-U8 is a GPS+BeiDou module
  // that can emit BD/GB GSV sentences TinyGPS++ ignores, in which case
  // satellites.isValid() never becomes true and a real fix gets rejected.
  // location.age() already rejects stale fixes.
  return gps.location.isValid() && gps.location.age() < GPS_FIX_MAX_AGE_MS;
}

static bool gpsHoldWanted(uint32_t now) {
  if (DEMO_LIVE_TRACKING) return true;                  // demo: keep the GPS session open continuously
  if (fallPending) return true;                         // pre-warm during the cancel window
  return emergencyActive && (now - emergencyStartMs) < EMERGENCY_FAST_PHASE_MS;
}

static uint32_t gpsBaseInterval() {
  if (emergencyActive)          return GPS_EMERGENCY_SLOW_MS;
  if (currentMode == MODE_RESTING) return GPS_RESTING_INTERVAL_MS;
  return geofenceCount > 0 ? GPS_ACTIVE_INTERVAL_MS : GPS_ACTIVE_NOFENCE_MS;
}

// Store the fix, decide whether to upload it, check geofences.
// Returns true if a geofence change needs another confirming fix.
static bool gpsAcceptFix(uint32_t now) {
  GpsFix f;
  f.valid = true;
  f.lat   = gps.location.lat();
  f.lng   = gps.location.lng();
  f.utc   = gpsUtcEpoch();
  f.atMs  = now;

  portENTER_CRITICAL(&fixMux);
  f.seq   = lastFix.seq + 1;
  lastFix = f;
  portEXIT_CRITICAL(&fixMux);

  float moved = reportedValid ? distanceMeters(reportedLat, reportedLng, f.lat, f.lng) : 1e9f;
  if (DEMO_LIVE_TRACKING || moved >= LOCATION_REPORT_MIN_MOVE_M || locateRequested) {
    reportedLat = f.lat; reportedLng = f.lng; reportedValid = true;
    locationReportPending = true;
  }
  if (locateRequested) locateRequested = false;

  return geofenceEvaluate(f.lat, f.lng, f.utc);
}

static void gpsEndSession(uint32_t now, bool ok) {
  gpsSession = false;
  uint32_t base = gpsBaseInterval();

  if (ok) {
    gpsFailCount = 0;
    gpsNextSession = now + base;
  } else {
    if (gpsFailCount < 6) gpsFailCount++;
    uint32_t backoff = base << (gpsFailCount > 3 ? 3 : gpsFailCount);
    uint32_t cap = (base > GPS_FAIL_BACKOFF_MAX_MS) ? base : GPS_FAIL_BACKOFF_MAX_MS;
    if (backoff > cap) backoff = cap;
    gpsNextSession = now + backoff;
    LOG("[GPS] No fix, next try in %lu s\n", (unsigned long)(backoff / 1000));
  }

  if (locateRequested) {                  // locate-now with no fix: report last known position
    locateRequested = false;
    if (getFix().valid) locationReportPending = true;
  }
  if (!gpsHoldWanted(now)) gpsPowerOff(now);
}

static void gpsUpdate(uint32_t now) {
  // One-time check that the module really obeys the stop command.
  if (gpsStopCheckAt && (int32_t)(now - gpsStopCheckAt) >= 0) {
    gpsStopCheckAt = 0;
    if (!gpsPowered) {
      gpsDutyVerified = true;
      if (gps.location.age() < 2500) {     // still getting fresh fixes -> command ignored
        gpsDutyOk = false;
        gpsPowered = true;
        LOG("[GPS] Stop command not supported by this module: duty cycling disabled\n");
      } else {
        LOG("[GPS] Duty cycling verified\n");
      }
    }
  }

  bool hold = gpsHoldWanted(now);

  if (hold) {
    gpsPowerOn();
    if (!gpsSession) { gpsSession = true; gpsSessionStart = now; gpsFirstFixAt = 0; gpsAcceptAfter = 0; }
  } else if (!gpsSession) {
    if (locateRequested || (int32_t)(now - gpsNextSession) >= 0) {
      gpsSession = true;
      gpsSessionStart = now;
      gpsFirstFixAt = 0;
      gpsAcceptAfter = 0;
      gpsPowerOn();
      LOG("[GPS] Session start\n");
    } else {
      gpsPowerOff(now);                   // leaving hold / idle between sessions
      return;
    }
  }

  if (gpsFixFresh()) {
    if (gpsFirstFixAt == 0) gpsFirstFixAt = now;
    bool settled = hold || (now - gpsFirstFixAt) >= GPS_SETTLE_MS;
    if (settled && (int32_t)(now - gpsAcceptAfter) >= 0) {
      bool needMore = gpsAcceptFix(now);
      if (hold) {
        gpsAcceptAfter = now + GPS_HOLD_ACCEPT_MS;
      } else if (needMore) {
        gpsAcceptAfter = now + GEOFENCE_CONFIRM_GAP_MS;   // keep GPS on for one more fix
        gpsSessionStart = now;
      } else {
        gpsEndSession(now, true);
      }
    }
  } else {
    gpsFirstFixAt = 0;
    if (!hold && (now - gpsSessionStart) > GPS_FIX_TIMEOUT_MS) gpsEndSession(now, false);
  }
}

// Dump GGA/RMC sentences verbatim (any talker ID) every ~5 s so we can see
// the raw fix status and coordinates. Removed once the GPS issue is resolved.
static void nmeaCapture(char c) {
#if LOG_ENABLED
  if (c == '$') nmeaLen = 0;
  if (nmeaLen < sizeof(nmeaBuf) - 1) nmeaBuf[nmeaLen++] = c;
  if (c == '\n') {
    int end = nmeaLen;
    if (end >= 2 && nmeaBuf[end - 1] == '\n' && nmeaBuf[end - 2] == '\r') end -= 2;
    nmeaBuf[end] = 0;
    if (end > 6) {
      bool isPos = (strncmp(nmeaBuf + 3, "GGA", 3) == 0) ||
                   (strncmp(nmeaBuf + 3, "RMC", 3) == 0);
      if (isPos && (millis() - lastNmeaDump) >= 5000) {
        lastNmeaDump = millis();
        LOG("[NMEA] %s\n", nmeaBuf);
      }
    }
  }
#endif
}

static void feedGps() {
  while (gpsSerial.available()) {
    char c = (char)gpsSerial.read();
    gps.encode(c);
    gpsRxWindow++;
    gpsRxTotal++;
    nmeaCapture(c);
  }
}


// ═══════════════════════════════════════════════════════════════════════════
//  13. POWER MODE  (RESTING / ACTIVE / EMERGENCY)
// ═══════════════════════════════════════════════════════════════════════════

static void modeUpdate(uint32_t now) {
  uint8_t m;
  if (emergencyActive || fallPending)         m = MODE_EMERGENCY;
  else if ((now - lastMotionMs) > REST_AFTER_MS) m = MODE_RESTING;
  else                                        m = MODE_ACTIVE;

  if (m == currentMode) return;
  LOG("[MODE] %s -> %s\n", modeName(currentMode), modeName(m));

  // Waking up from rest: take a fresh fix soon instead of waiting out the long interval
  if (currentMode == MODE_RESTING && m == MODE_ACTIVE && !gpsSession) {
    if ((int32_t)(gpsNextSession - (now + 15000)) > 0) gpsNextSession = now + 15000;
  }
  currentMode = m;
}


// ═══════════════════════════════════════════════════════════════════════════
//  14. FIREBASE REST CLIENT  (small, keep-alive, no external library)
// ═══════════════════════════════════════════════════════════════════════════

static String dbUrl(const String& path) {
  return String(FIREBASE_HOST) + path + ".json?auth=" + authToken;
}

static bool dbOk(int code) { return code >= 200 && code < 300; }

// Returns the HTTP status code, or a negative value on a transport error.
static int dbRequest(const char* method, const String& path, const String& body, String* out) {
  http.setReuse(true);
  http.setConnectTimeout(6000);
  http.setTimeout(8000);
  if (!http.begin(netClient, dbUrl(path))) return -1;

  int code;
  if (strcmp(method, "GET") == 0) {
    code = http.GET();
  } else {
    http.addHeader("Content-Type", "application/json");
    code = http.sendRequest(method, body);
  }
  if (out && code > 0) *out = http.getString();
  http.end();

  if (code == 401 || code == 403) authExpiryMs = 0;     // force a new token next time
  if (code < 0) LOG("[NET] %s %s failed: %s\n", method, path.c_str(), HTTPClient::errorToString(code).c_str());
  return code;
}

static bool dbPatchDevice(const String& body) {
  return dbOk(dbRequest("PATCH", devBase, body, nullptr));
}

#if AUTH_EMAIL_MODE
static bool signInWithEmail() {
  WiFiClientSecure c;
  c.setInsecure();
  HTTPClient h;
  String url = String("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=") + FIREBASE_API_KEY;
  if (!h.begin(c, url)) return false;
  h.addHeader("Content-Type", "application/json");

  StaticJsonDocument<256> req;
  req["email"] = FIREBASE_AUTH_EMAIL;
  req["password"] = FIREBASE_AUTH_PASSWORD;
  req["returnSecureToken"] = true;
  String body;
  serializeJson(req, body);

  int code = h.POST(body);
  if (code != 200) { h.end(); LOG("[AUTH] Sign-in failed (%d)\n", code); return false; }
  String resp = h.getString();
  h.end();

  DynamicJsonDocument doc(4096);
  if (deserializeJson(doc, resp)) return false;
  const char* tok = doc["idToken"];
  if (!tok) return false;
  authToken = tok;
  uint32_t ttl = (uint32_t)atoi(doc["expiresIn"] | "3600");
  authExpiryMs = millis() + ttl * 1000UL;
  LOG("[AUTH] Signed in\n");
  return true;
}
#endif

static bool authEnsure() {
#if AUTH_EMAIL_MODE
  if (authToken.length() && (int32_t)(authExpiryMs - millis()) > 60000) return true;
  return signInWithEmail();
#else
  return true;                // legacy secret is used as-is
#endif
}


// ═══════════════════════════════════════════════════════════════════════════
//  15. NETWORK TASK  (runs on its own core; the sensing loop is never blocked)
// ═══════════════════════════════════════════════════════════════════════════

static uint32_t heartbeatMs(uint8_t mode)   { return mode == MODE_ACTIVE ? HEARTBEAT_ACTIVE_MS : HEARTBEAT_RESTING_MS; }
static uint32_t commandPollMs(uint8_t mode) { return mode == MODE_ACTIVE ? COMMAND_POLL_ACTIVE_MS : COMMAND_POLL_RESTING_MS; }

static bool sendAlert() {
  char reason[sizeof(alertReason)];
  bool fall;
  portENTER_CRITICAL(&alertMux);
  strlcpy(reason, alertReason, sizeof(reason));
  fall = fallFlag;
  portEXIT_CRITICAL(&alertMux);

  GpsFix fix = getFix();

  StaticJsonDocument<768> doc;
  doc["emergency/active"] = true;
  doc["emergency/reason"] = reason;
  doc["emergency/triggeredAt"][".sv"] = "timestamp";
  doc["sensors/fallDetected"] = fall;
  if (fix.valid) {
    doc["emergency/lat"]     = fix.lat;
    doc["emergency/lng"]     = fix.lng;
    doc["emergency/locAgeS"] = (millis() - fix.atMs) / 1000;
    if (fix.utc) doc["emergency/eventUtc"] = fixUtcNow(fix);
  }
  String body;
  serializeJson(doc, body);
  return dbPatchDevice(body);
}

static bool sendEmergencyLocation(uint32_t& sentSeq) {
  GpsFix fix = getFix();
  if (!fix.valid) return true;

  StaticJsonDocument<512> doc;
  doc["emergency/lat"]     = fix.lat;
  doc["emergency/lng"]     = fix.lng;
  doc["emergency/locAgeS"] = (millis() - fix.atMs) / 1000;
  doc["sensors/gps/lat"]   = fix.lat;
  doc["sensors/gps/lng"]   = fix.lng;
  if (fix.utc) doc["sensors/gps/fixUtc"] = fixUtcNow(fix);
  doc["sensors/timestamp"][".sv"] = "timestamp";
  String body;
  serializeJson(doc, body);
  if (!dbPatchDevice(body)) return false;
  sentSeq = fix.seq;
  return true;
}

static bool sendLocationReport() {
  GpsFix fix = getFix();
  if (!fix.valid) { locationReportPending = false; return true; }

  StaticJsonDocument<384> doc;
  doc["sensors/gps/lat"] = fix.lat;
  doc["sensors/gps/lng"] = fix.lng;
  if (fix.utc) doc["sensors/gps/fixUtc"] = fixUtcNow(fix);
  doc["sensors/timestamp"][".sv"] = "timestamp";
  String body;
  serializeJson(doc, body);
  if (!dbPatchDevice(body)) return false;
  locationReportPending = false;
  return true;
}

static bool sendHeartbeat(uint32_t now) {
  GpsFix fix = getFix();

  StaticJsonDocument<1024> doc;
  doc["sensors/online"]              = true;
  doc["sensors/timestamp"][".sv"]    = "timestamp";
  doc["sensors/mode"]                = modeName(currentMode);
  doc["sensors/hbIntervalS"]         = heartbeatMs(currentMode) / 1000;
  doc["sensors/rssi"]                = WiFi.RSSI();
  doc["sensors/imuOk"]               = (bool)imuOk;
  doc["sensors/firmware"]            = FW_VERSION;
  doc["sensors/fallDetected"]        = (bool)fallFlag;
  doc["sensors/accelerometer/x"]     = (float)lastAx;
  doc["sensors/accelerometer/y"]     = (float)lastAy;
  doc["sensors/accelerometer/z"]     = (float)lastAz;
  if (fix.valid) {
    doc["sensors/gps/lat"] = fix.lat;
    doc["sensors/gps/lng"] = fix.lng;
    if (fix.utc) doc["sensors/gps/fixUtc"] = fixUtcNow(fix);
  }
  String body;
  serializeJson(doc, body);
  (void)now;
  if (!dbPatchDevice(body)) return false;
  if (fix.valid && fix.seq == getFix().seq) locationReportPending = false;
  return true;
}

static bool sendGeoEvent(const GeoEvent& ev) {
  StaticJsonDocument<768> doc;
  doc["geofenceId"] = ev.id;
  doc["name"]       = ev.name;
  doc["type"]       = ev.entered ? "entered" : "exited";
  doc["lat"]        = ev.lat;
  doc["lng"]        = ev.lng;
  doc["distance"]   = ev.distance;
  if (ev.utc) doc["eventUtc"] = ev.utc;
  doc["timestamp"][".sv"] = "timestamp";
  String body;
  serializeJson(doc, body);
  return dbOk(dbRequest("POST", devBase + "/geofence_violations", body, nullptr));
}

// ── Push/SMS webhook (Netlify function) ──────────────────────────────────────
// Turns an emergency/geofence event into FCM push + SMS via the Netlify
// function. Best-effort only: a failure here never blocks RTDB delivery.

static void notifyWebhook(const char* kind, const String& body) {
#if defined(NOTIFY_WEBHOOK_URL)
  if (NOTIFY_WEBHOOK_URL[0] == '\0') return;
  WiFiClientSecure c;
  c.setInsecure();
  HTTPClient h;
  if (!h.begin(c, NOTIFY_WEBHOOK_URL)) {
    LOG("[NOTIFY] begin failed\n");
    return;
  }
  h.addHeader("Content-Type", "application/json");
  int code = h.POST(body);
  LOG("[NOTIFY] %s -> %d\n", kind, code);
  h.end();
#else
  (void)kind; (void)body;
#endif
}

static void notifyEmergencyWebhook() {
  GpsFix fix = getFix();
  char reason[sizeof(alertReason)];
  bool fall;
  portENTER_CRITICAL(&alertMux);
  strlcpy(reason, alertReason, sizeof(reason));
  fall = fallFlag;
  portEXIT_CRITICAL(&alertMux);

  StaticJsonDocument<384> doc;
  doc["kind"]     = "emergency";
  doc["deviceId"] = deviceId;
  doc["reason"]   = reason;
  doc["type"]     = fall ? "fall" : "sos";
  if (fix.valid) {
    doc["lat"] = fix.lat;
    doc["lng"] = fix.lng;
  }
  String body;
  serializeJson(doc, body);
  notifyWebhook("emergency", body);
}

static void notifyGeoWebhook(const GeoEvent& ev) {
  StaticJsonDocument<384> doc;
  doc["kind"]       = "geofence";
  doc["deviceId"]   = deviceId;
  doc["type"]       = ev.entered ? "entered" : "exited";
  doc["name"]       = ev.name;
  doc["geofenceId"] = ev.id;
  doc["lat"]        = ev.lat;
  doc["lng"]        = ev.lng;
  String body;
  serializeJson(doc, body);
  notifyWebhook("geofence", body);
}

static bool fetchGeofences() {
  String body;
  int code = dbRequest("GET", devBase + "/geofences", "", &body);
  if (!dbOk(code)) return false;
  body.trim();

  int n = 0;
  if (body.length() > 0 && body != "null") {
    if (!parseGeofences(body, geoScratch, n)) {
      LOG("[GEOFENCE] Could not parse geofence JSON, keeping previous list\n");
      return false;
    }
  }
  applyGeofences(geoScratch, n);
  return true;
}

// Reads /commands: { locateNow: bool, refreshGeofences: bool }, clears what it handled.
static bool pollCommands() {
  String body;
  int code = dbRequest("GET", devBase + "/commands", "", &body);
  if (!dbOk(code)) return false;
  body.trim();
  if (body.length() < 3 || body == "null") return true;

  StaticJsonDocument<256> doc;
  if (deserializeJson(doc, body)) return true;

  bool locate  = doc["locateNow"] | false;
  bool refresh = doc["refreshGeofences"] | false;
  if (!locate && !refresh) return true;

  StaticJsonDocument<128> clr;
  if (locate)  { locateRequested = true;          clr["commands/locateNow"] = false; }
  if (refresh) { geofenceRefreshRequested = true; clr["commands/refreshGeofences"] = false; }
  String out;
  serializeJson(clr, out);
  dbPatchDevice(out);
  LOG("[CMD] locateNow=%d refreshGeofences=%d\n", locate, refresh);
  return true;
}

// Returns true if the app has cleared the emergency (active == false).
static bool emergencyClearedByApp(bool& requestOk) {
  String body;
  int code = dbRequest("GET", devBase + "/emergency/active", "", &body);
  requestOk = dbOk(code);
  if (!requestOk) return false;
  body.trim();
  return body == "false";
}

// Keeps WiFi associated (modem sleep) and reconnects with back-off. Cheap when connected.
static bool wifiEnsure(uint32_t now, uint32_t& nextAttempt, uint32_t& backoff) {
  if (WiFi.status() == WL_CONNECTED) {
    if (!wifiUp) {
      wifiUp = true;
      backoff = WIFI_RETRY_MIN_MS;
      WiFi.setSleep(WIFI_PS_MAX_MODEM);
      LOG("[WIFI] Connected: %s  (%s)\n", WiFi.SSID().c_str(), WiFi.localIP().toString().c_str());
    }
    return true;
  }

  wifiUp = false;
  if ((int32_t)(now - nextAttempt) < 0) return false;

  cpuBoost();
  LOG("[WIFI] Connecting...\n");
  wifiMulti.run(WIFI_CONNECT_TIMEOUT_MS);
  cpuRelax();

  if (WiFi.status() == WL_CONNECTED) return true;       // marked up on the next call

  uint32_t wait = backoff;
  if (emergencyActive && !alertDelivered) wait = WIFI_RETRY_EMERGENCY_MS;
  nextAttempt = millis() + wait;
  backoff = backoff * 2;
  if (backoff > WIFI_RETRY_MAX_MS) backoff = WIFI_RETRY_MAX_MS;
  return false;
}

static void netTask(void* arg) {
  (void)arg;

  uint32_t lastHb = 0, lastCmd = 0, lastGeo = 0, lastEmgPoll = 0, lastEmgLoc = 0;
  uint32_t nextAlertTry = 0, nextWifiAttempt = 0, wifiBackoff = WIFI_RETRY_MIN_MS;
  uint32_t netBackoffUntil = 0, netBackoff = NET_BACKOFF_MIN_MS;
  uint32_t emgSentSeq = 0;
  uint32_t lastOkMs = millis();
  bool firstSync = true;

  for (;;) {
    // Sleep until woken (alert / geofence event) or the 1 s tick; the CPU is idle meanwhile.
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(emergencyActive ? 250 : 1000));
    uint32_t now = millis();

    if (!wifiEnsure(now, nextWifiAttempt, wifiBackoff)) continue;
    if ((int32_t)(now - netBackoffUntil) < 0) continue;

    const uint8_t mode = currentMode;
    const bool emgSession  = emergencyActive;
    const bool emgDelivered = emgSession && alertDelivered;
    const bool emgFast     = (now - emergencyStartMs) < EMERGENCY_FAST_PHASE_MS;

    bool alertDue    = alertPending && (int32_t)(now - nextAlertTry) >= 0;
    bool emgPollDue  = emgDelivered && (now - lastEmgPoll) >= (emgFast ? EMG_POLL_FAST_MS : EMG_POLL_SLOW_MS);
    bool emgLocDue   = emgDelivered && (now - lastEmgLoc)  >= (emgFast ? EMG_LOC_FAST_MS  : EMG_LOC_SLOW_MS)
                       && getFix().seq != emgSentSeq;
    bool geoEvtDue   = uxQueueMessagesWaiting(geoQueue) > 0;
    bool locDue      = locationReportPending && !emgSession;
    bool hbDue       = !emgSession && (firstSync || (now - lastHb) >= heartbeatMs(mode));
    bool cmdDue      = !emgSession && ENABLE_COMMAND_POLL && (now - lastCmd) >= commandPollMs(mode);
    bool geoFetchDue = !emgSession && (firstSync || geofenceRefreshRequested || (now - lastGeo) >= GEOFENCE_REFRESH_MS);

    if (!(alertDue || emgPollDue || emgLocDue || geoEvtDue || locDue || hbDue || cmdDue || geoFetchDue)) {
      // Nothing to do. If WiFi is up but nothing has worked for an hour, reboot as a last resort.
      if (!emgSession && (now - lastOkMs) > NET_STALL_RESTART_MS) ESP.restart();
      continue;
    }

    cpuBoost();
    bool failed = false;

    if (!authEnsure()) {
      failed = true;
    } else {
      // 1) The emergency alert always goes first
      if (alertDue) {
        if (sendAlert()) {
          alertPending = false;
          alertDelivered = true;
          lastEmgPoll = now;
          lastEmgLoc = now;
          emgSentSeq = getFix().seq;
          notifyEmergencyWebhook();
          LOG("[NET] Emergency alert delivered\n");
        } else {
          nextAlertTry = now + ALERT_RETRY_MS;
          failed = true;
        }
      }

      // 2) Emergency follow-up: has the app cleared it? send fresh location
      if (!failed && emgPollDue) {
        bool ok;
        bool cleared = emergencyClearedByApp(ok);
        if (!ok) failed = true;
        else {
          lastEmgPoll = now;
          if (cleared) {
            StaticJsonDocument<64> d;
            d["sensors/fallDetected"] = false;
            String b;
            serializeJson(d, b);
            dbPatchDevice(b);
            emergencyClearRequest = true;
            LOG("[NET] Emergency cleared from app\n");
          }
        }
      }
      if (!failed && emgLocDue) {
        if (sendEmergencyLocation(emgSentSeq)) lastEmgLoc = now; else failed = true;
      }

      // 3) Geofence enter / exit events (kept in the queue until delivered)
      if (!failed && geoEvtDue) {
        GeoEvent ev;
        while (xQueuePeek(geoQueue, &ev, 0) == pdTRUE) {
          if (sendGeoEvent(ev)) { xQueueReceive(geoQueue, &ev, 0); notifyGeoWebhook(ev); }
          else { failed = true; break; }
        }
      }

      // 4) Location report, heartbeat, commands, geofence refresh
      if (!failed && locDue)      { if (!sendLocationReport()) failed = true; }
      if (!failed && hbDue)       { if (sendHeartbeat(now)) { lastHb = now; } else failed = true; }
      if (!failed && geoFetchDue) {
        if (fetchGeofences()) { lastGeo = now; geofenceRefreshRequested = false; } else failed = true;
      }
      if (!failed && cmdDue)      { if (pollCommands()) lastCmd = now; else failed = true; }
      if (!failed) firstSync = false;
    }

    cpuRelax();

    if (failed) {
      uint32_t cap = (alertPending || emergencyActive) ? 8000 : NET_BACKOFF_MAX_MS;
      netBackoffUntil = millis() + netBackoff;
      netBackoff = netBackoff * 2;
      if (netBackoff > cap) netBackoff = cap;
    } else {
      netBackoff = NET_BACKOFF_MIN_MS;
      lastOkMs = millis();
    }
  }
}


// ═══════════════════════════════════════════════════════════════════════════
//  16. SETUP
// ═══════════════════════════════════════════════════════════════════════════

// Holding the button for 5 s while powering up erases the saved WiFi networks.
static bool bootHoldRequested() {
  if (digitalRead(PIN_SOS) != LOW) return false;
  uint32_t t0 = millis();
  while (digitalRead(PIN_SOS) == LOW) {
    uint32_t held = millis() - t0;
    digitalWrite(PIN_LED, ((held / 100) % 2) ? HIGH : LOW);
    if (held >= BOOT_HOLD_MS) {
      digitalWrite(PIN_LED, HIGH);
      uint32_t w = millis();
      while (digitalRead(PIN_SOS) == LOW && millis() - w < 5000) delay(10);
      digitalWrite(PIN_LED, LOW);
      return true;
    }
    delay(20);
  }
  digitalWrite(PIN_LED, LOW);
  return false;
}

static bool connectBlocking(uint32_t timeoutMs) {
  registerWifiNetworks();
  wifiMulti.run(timeoutMs);
  return WiFi.status() == WL_CONNECTED;
}

static void startNormalOperation() {
  registerWifiNetworks();
  devBase = String("/devices/") + deviceId;

#if !AUTH_EMAIL_MODE
  authToken = FIREBASE_AUTH;
#endif

  geoMutex = xSemaphoreCreateMutex();
  geoQueue = xQueueCreate(GEO_QUEUE_LEN, sizeof(GeoEvent));
  netClient.setInsecure();      // see CHANGES.md "Known limitations" about TLS verification

  uint32_t now = millis();
  lastMotionMs   = now;
  gpsNextSession = now;         // first GPS session right away

  xTaskCreatePinnedToCore(netTask, "net", 16384, nullptr, 1, &netTaskHandle, 0);
  normalOperation = true;

  LOG("\n=== Guardian %s started ===\n", FW_VERSION);
  LOG("Device ID: %s\n", deviceId.c_str());
}

void setup() {
  Serial.begin(115200);
#if defined(ARDUINO_USB_CDC_ON_BOOT) && ARDUINO_USB_CDC_ON_BOOT
  Serial.setTxTimeoutMs(0);     // never block when no USB host is attached (battery use)
#endif
#if LOG_ENABLED
  uint32_t t0 = millis();
  while (!Serial && (millis() - t0) < 1500) delay(10);
#endif

  setCpuFrequencyMhz(CPU_MHZ_IDLE);

  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, LOW);
  pinMode(PIN_SOS, INPUT_PULLUP);

  gpsSerial.setRxBufferSize(512);
  gpsSerial.begin(9600, SERIAL_8N1, PIN_GPS_RX, PIN_GPS_TX);

  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(400000);
  imuInit();

  // Read the base MAC straight from eFuse — WiFi.macAddress() can return
  // 00:00:00:00:00:00 before the WiFi driver has fully initialized on the S3.
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macBuf[13];
  snprintf(macBuf, sizeof(macBuf), "%02x%02x%02x%02x%02x%02x",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  macHex = macBuf;
  String macUp = macHex;
  macUp.toUpperCase();
  shortName = "Guardian_" + macUp.substring(macUp.length() - 4);

  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);

  loadConfig();

  if (bootHoldRequested()) {
    LOG("[BOOT] Button held: clearing saved WiFi networks\n");
    clearWifiNetworks();
  }

  attachInterrupt(digitalPinToInterrupt(PIN_SOS), onSosEdge, FALLING);

  bool wasFresh = takeFreshFlag();

  if (netCount == 0) {
    LOG("[BOOT] No WiFi saved -> provisioning\n");
    startProvisioning();
    return;
  }

  if (wasFresh) {
    // Credentials were just entered in the app: verify them now, and reopen setup if they fail.
    LOG("[BOOT] Verifying new WiFi credentials...\n");
    if (!connectBlocking(FRESH_WIFI_TIMEOUT_MS)) {
      LOG("[BOOT] New credentials did not connect -> provisioning\n");
      startProvisioning();
      return;
    }
  }

  // Normal operation. If WiFi is simply unavailable right now, the network task keeps
  // retrying in the background while fall detection and the SOS button already work.
  startNormalOperation();
}


// ═══════════════════════════════════════════════════════════════════════════
//  17. MAIN LOOP  (sensing only: IMU, button, GPS parsing, LED, mode)
// ═══════════════════════════════════════════════════════════════════════════

static void statusLog(uint32_t now) {
#if LOG_ENABLED
  static uint32_t last = 0;
  if (now - last < 30000) return;
  last = now;
  GpsFix f = getFix();
  LOG("[STATUS] mode=%s wifi=%s gps=%s fix=%s rx=%lu/%lu imu=%s fences=%d heap=%u\n",
      modeName(currentMode), wifiUp ? "up" : "down",
      gpsPowered ? "on" : "off", f.valid ? "yes" : "no",
      (unsigned long)gpsRxWindow, (unsigned long)gpsRxTotal,
      imuOk ? "ok" : "FAULT", (int)geofenceCount, (unsigned)ESP.getFreeHeap());
  gpsRxWindow = 0;
#else
  (void)now;
#endif
}

void loop() {
  const uint32_t now = millis();

  if (!normalOperation) {          // BLE provisioning / idle
    provisioningLoop(now);
    return;
  }

  feedGps();
  handleButton(now);

  if (now - lastImuSampleMs >= IMU_SAMPLE_MS) {
    lastImuSampleMs = now;
    imuSample(now);
  }

  // The cancel window ran out without a hold-to-cancel: send the fall alert.
  if (fallPending && (now - fallPendingSince) >= FALL_CANCEL_WINDOW_MS) {
    fallPending = false;
    fallIgnoreUntil = now + FALL_COOLDOWN_MS;
    triggerEmergency("Fall detected by accelerometer", true, now);
  }

  // The app cleared the emergency.
  if (emergencyClearRequest) {
    emergencyClearRequest = false;
    emergencyActive = false;
    alertDelivered  = false;
    alertPending    = false;
    fallFlag        = false;
    fallIgnoreUntil = now + FALL_COOLDOWN_MS;
    LOG("[EMERGENCY] Cleared\n");
  }

  modeUpdate(now);
  gpsUpdate(now);
  ledUpdate(now);
  statusLog(now);

  delay(2);                        // yields to the idle task so the CPU can rest
}
