// ═══════════════════════════════════════════════════════════════════
// ESP32 FIRMWARE CONFIGURATION TEMPLATE
// Replace values below with YOUR actual credentials
// ═══════════════════════════════════════════════════════════════════

// 1️⃣ WIFI NETWORK - Your home/office WiFi
#define WIFI_SSID           "YourWiFiNetworkName"
#define WIFI_PASSWORD       "YourWiFiPassword123"

// 2️⃣ FIREBASE PROJECT - From your Firebase Console
#define FIREBASE_HOST       "guardian-abc123.firebaseio.com"  // Get from: Realtime Database → Address bar
#define FIREBASE_AUTH       "abcd1234efgh5678ijkl9012mnop3456"  // Get from: Database → Settings → Secrets → Database Secret

// 3️⃣ DEVICE IDENTIFICATION
#define DEVICE_ID           "esp32_device_1"  // Must match value in app (lib/screens/home_screen.dart line 32)

// ═══════════════════════════════════════════════════════════════════

// WHERE TO FIND YOUR FIREBASE CREDENTIALS:
//
// === FIREBASE HOST ===
// 1. Go to Firebase Console → Your Project
// 2. Click "Realtime Database"
// 3. The URL at the top is like: https://guardian-abc123.firebaseio.com
// 4. Use "guardian-abc123.firebaseio.com" (without https://)
//
// === DATABASE SECRET ===
// 1. In Realtime Database → Click Settings icon (⚙️) → "Database secrets" tab
// 2. Copy the token that appears
// 3. Paste it as FIREBASE_AUTH
//
// === DEVICE ID ===
// 1. This must match hardcoded device ID in Flutter app
// 2. Currently set to "esp32_device_1" in app
// 3. If you change it, update it in BOTH places:
//    - ESP32: #define DEVICE_ID
//    - Flutter app: lib/screens/home_screen.dart (line 32)
//
// ═══════════════════════════════════════════════════════════════════

// OPTIONAL: Fall Detection Threshold Tuning
#define FALL_ACCEL_THRESHOLD   2.5   // Higher = less sensitive (fewer false alarms)
                                      // Lower = more sensitive (more false alarms)
                                      // Default 2.5g works for most falls

#define FALL_COOLDOWN_MS       5000  // Wait 5s before detecting another fall
#define UPDATE_INTERVAL_MS     2000  // Send data to Firebase every 2 seconds

// ═══════════════════════════════════════════════════════════════════
// PIN CONFIGURATION
//
// MPU6050 (Accelerometer):   I2C (SCL=22, SDA=21 - default)
// GPS Module:                Serial2 (RX=16, TX=17)
// SOS Button:                GPIO 0 (Boot button) or any GPIO
// LED:                       GPIO 2 (Built-in LED)
//
// ═══════════════════════════════════════════════════════════════════

// TROUBLESHOOTING CHECKLIST:
//
// ❌ "Not connecting to Firebase" → Check FIREBASE_HOST and FIREBASE_AUTH
// ❌ "Not connecting to WiFi" → Check WIFI_SSID and WIFI_PASSWORD spelling
// ❌ "Device shows offline in app" → Check if /esp32_device_1/sensors path exists in Firebase
// ❌ "GPS data is 0.0, 0.0" → Wait 5-10 mins outdoors for GPS lock
// ❌ "Fall detection too sensitive" → Increase FALL_ACCEL_THRESHOLD to 3.0 or higher
// ❌ "Can't upload to board" → Check USB cable, baud rate (115200), and board selection (ESP32 Dev Module)
//
// ═══════════════════════════════════════════════════════════════════
