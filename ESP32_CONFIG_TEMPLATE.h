// ═══════════════════════════════════════════════════════════════
// GUARDIAN ESP32 FIRMWARE — CONFIGURATION TEMPLATE (v2.0.0)
//
// In v2, private settings live in `secrets.h` (next to the .ino),
// and every tunable value lives in section 1 of guardian_firmware.ino.
// This file documents where to put things.
//
//   cp ESP32_CONFIG_TEMPLATE.h secrets.h   # then fill in your values
//   gitignore secrets.h                    # NEVER commit it
// ═══════════════════════════════════════════════════════════════

// 1️⃣ FIREBASE — copy these into secrets.h
#define FIREBASE_HOST  "https://YOUR_PROJECT-default-rtdb.firebaseio.com"

// Push/SMS webhook (Netlify function) — leave empty ("") to disable
#define NOTIFY_WEBHOOK_URL  "https://YOUR-SITE.netlify.app/.netlify/functions/notify"

// Choose ONE auth option:
//   OPTION A — legacy database secret (simplest, bypasses security rules)
#define FIREBASE_AUTH  "PASTE_NEW_DATABASE_SECRET_HERE"
//   OPTION B — per-device email/password sign-in (recommended)
// #define FIREBASE_API_KEY        "YOUR_WEB_API_KEY"
// #define FIREBASE_AUTH_EMAIL     "guardian@yourdomain.com"
// #define FIREBASE_AUTH_PASSWORD  "device-password"

// Optional BLE provisioning PIN (empty = no PIN)
#define PROVISIONING_PIN  ""

// 2️⃣ TUNING — all constants live in section 1 of guardian_firmware.ino
//   Fall detection:  FREEFALL_G, IMPACT_G (2.5g), IMPACT_STRONG_G (3.5g),
//                    FALL_CANCEL_WINDOW_MS (15 s "I'm OK" window)
//   Heartbeat:       HEARTBEAT_ACTIVE_MS (2 min), HEARTBEAT_RESTING_MS (5 min)
//   GPS duty cycle:  GPS_DUTY_CYCLE, GPS_ACTIVE_INTERVAL_MS, GPS_RESTING_INTERVAL_MS
//   Power modes:     MOTION_DEVIATION_G, REST_AFTER_MS

// 3️⃣ DEVICE ID — auto-generated as "guardian_<mac>" at boot, stored in NVS,
//   and provisioned to the app over BLE. There is no hardcoded DEVICE_ID.
//   The app stores it in Firestore (users/{uid}/deviceId) during BLE setup.

// 4️⃣ LIBRARIES (Arduino Library Manager)
//   - TinyGPSPlus       by Mikal Hart
//   - MPU6050           by Electronic Cats
//   - ArduinoJson       by Benoit Blanchon (6.x recommended)
//   (WiFi, HTTPClient, Preferences, BLE come with the ESP32 core)
//   The old "Firebase ESP32 Client" (mobizt) is NOT used any more.

// ═══════════════════════════════════════════════════════════════
// PIN CONFIGURATION (ESP32-S3 SuperMini) — unchanged from v1
//
// MPU6050 (Accelerometer):   I2C (SDA=8, SCL=9)
// GPS Module (GT-U8):        Serial2 (RX=5, TX=6)
// SOS Button:                GPIO 4 (active LOW, internal pull-up)
// Status LED:                GPIO 2 (external single-color LED, active HIGH via 220 Ω)
//
// TROUBLESHOOTING:
// ❌ "No WiFi saved -> provisioning" → provision WiFi from the app over BLE
// ❌ "Device shows offline in app"   → check /devices/guardian_<mac>/sensors/timestamp freshness
// ❌ "GPS data is 0.0, 0.0"          → wait 5-10 mins outdoors for first GPS lock
// ❌ "Fall detection too sensitive"  → raise IMPACT_G / IMPACT_STRONG_G in section 1
// ❌ "Can't upload"                  → check board selection (ESP32S3 Dev Module) + USB CDC On Boot
// ═══════════════════════════════════════════════════════════════
