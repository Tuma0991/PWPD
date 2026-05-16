/*
  ═══════════════════════════════════════════════════════════════════
  Guardian ESP32 Firmware
  IoT Wearable Protection Device
  ═══════════════════════════════════════════════════════════════════

  Hardware:
    - ESP32 (any variant)
    - MPU6050 (Accelerometer/Gyroscope) via I2C
    - NEO-6M GPS Module via Serial2
    - (Optional) Push button on GPIO 0 for manual SOS

  Libraries required (install via Arduino Library Manager):
    - Firebase ESP32 Client by mobizt
    - TinyGPS++ by Mikal Hart
    - MPU6050 by Electronic Cats (or Adafruit MPU6050)
    - ArduinoJson by Benoit Blanchon

  ═══════════════════════════════════════════════════════════════════
*/

#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <TinyGPS++.h>
#include <Wire.h>
#include <MPU6050.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

// ─── Firebase Config ──────────────────────────────────────────────────────────
#define FIREBASE_HOST   "https://pwpd-5e580-default-rtdb.firebaseio.com"
#define FIREBASE_AUTH   "sr2NtPXykxRmnrVuYu4ilmFodKHDkLNHKRFe3AwG"

// ─── BLE Provisioning UUIDs ───────────────────────────────────────────────────
#define SERVICE_UUID              "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_UUID_DEVICE_INFO     "4fafc202-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_UUID_WIFI_CREDS      "4fafc203-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_UUID_PROV_STATUS     "4fafc204-1fb5-459e-8fcc-c5c9c331914b"

// ─── NVS Keys ─────────────────────────────────────────────────────────────────
#define NVS_NAMESPACE           "guardian"
#define NVS_KEY_WIFI_SSID       "wifi_ssid"
#define NVS_KEY_WIFI_PASS       "wifi_pass"
#define NVS_KEY_DEVICE_ID       "device_id"

// ─── WiFi Connection Timeout ──────────────────────────────────────────────────
#define WIFI_CONNECT_TIMEOUT_MS   15000

// ─── Pin Config ───────────────────────────────────────────────────────────────
#define GPS_RX_PIN      16    // ESP32 RX2
#define GPS_TX_PIN      17    // ESP32 TX2
#define SOS_BUTTON_PIN  4     // Emergency button
#define LED_PIN         2     // Built-in LED

// ─── Fall Detection Threshold ─────────────────────────────────────────────────
#define FALL_ACCEL_THRESHOLD   2.5   // in g-force units
#define FALL_COOLDOWN_MS       5000  // 5 seconds before re-detecting

// ─── SOS Button Config ────────────────────────────────────────────────────────
// FIX: After SOS is pressed, suppress fall detection for this duration.
// This prevents the button-press jolt from also triggering a fall alert.
#define SOS_FALL_SUPPRESS_MS   3000  // 3 seconds suppression after SOS press

// ─── Geofence Config ──────────────────────────────────────────────────────────
#define GEOFENCE_CHECK_INTERVAL_MS 30000
#define MAX_GEOFENCES 10

// ─── Update Interval ─────────────────────────────────────────────────────────
#define UPDATE_INTERVAL_MS     2000  // Push data to Firebase every 2s

// ─── Geofence Structure ───────────────────────────────────────────────────────
struct Geofence {
  char id[32];
  char name[64];
  double latitude;
  double longitude;
  float radiusMeters;
};

// ─── Objects ─────────────────────────────────────────────────────────────────
FirebaseData fbdo;
FirebaseAuth fbAuth;
FirebaseConfig fbConfig;
TinyGPSPlus gps;
MPU6050 mpu;
HardwareSerial gpsSerial(2);

// ─── State ───────────────────────────────────────────────────────────────────
bool fallDetected = false;
bool emergencyActive = false;
bool lastButtonState = HIGH;
unsigned long lastFallTime = 0;
unsigned long lastUpdateTime = 0;
unsigned long lastButtonPressTime = 0;
unsigned long lastDiagnosticTime = 0;
unsigned long lastGeofenceCheckTime = 0;

// FIX: Track when SOS was last triggered so we can suppress fall detection
unsigned long lastSOSTime = 0;

// FIX: Non-blocking LED blink state for emergency flash
bool emergencyLedOn = false;
unsigned long lastLedToggleTime = 0;
int emergencyLedFlashCount = 0;
bool isFlashingEmergency = false;

const unsigned long BUTTON_DEBOUNCE_MS = 50;   // FIX: reduced from 500ms — fast response
const unsigned long DIAGNOSTIC_INTERVAL_MS = 10000;

// Geofence state
Geofence geofences[MAX_GEOFENCES];
int geofenceCount = 0;
bool lastGeofenceStatus[MAX_GEOFENCES] = {false};

// BLE & NVS state
Preferences preferences;
bool provisioningMode = false;
String deviceId = "";
String wifiSSID = "";
String wifiPassword = "";

// ─── Helpers ─────────────────────────────────────────────────────────────────

String generateDeviceIdFromMAC() {
  String mac = WiFi.macAddress();
  mac.replace(":", "");
  mac.toLowerCase();
  return "guardian_" + mac;
}

String getShortName() {
  String mac = WiFi.macAddress();
  mac.replace(":", "");
  mac.toUpperCase();
  return "Guardian_" + mac.substring(mac.length() - 4);
}

String buildDeviceInfoJSON() {
  StaticJsonDocument<256> doc;
  doc["deviceId"] = deviceId;
  doc["firmware"] = "1.0.0";
  doc["wifiConfigured"] = (wifiSSID.length() > 0);
  doc["wifiConnected"] = (WiFi.status() == WL_CONNECTED);
  String json;
  serializeJson(doc, json);
  return json;
}

bool loadStoredConfig() {
  preferences.begin(NVS_NAMESPACE, false);
  wifiSSID = preferences.getString(NVS_KEY_WIFI_SSID, "");
  wifiPassword = preferences.getString(NVS_KEY_WIFI_PASS, "");
  deviceId = preferences.getString(NVS_KEY_DEVICE_ID, "");

  if (deviceId.length() == 0) {
    deviceId = generateDeviceIdFromMAC();
    preferences.putString(NVS_KEY_DEVICE_ID, deviceId);
  }

  preferences.end();
  Serial.printf("[CONFIG] Device ID: %s\n", deviceId.c_str());
  Serial.printf("[CONFIG] Stored WiFi: %s\n", wifiSSID.length() > 0 ? wifiSSID.c_str() : "(none)");
  return wifiSSID.length() > 0;
}

void saveWiFiCredentials(const char* ssid, const char* pass) {
  preferences.begin(NVS_NAMESPACE, false);
  preferences.putString(NVS_KEY_WIFI_SSID, ssid);
  preferences.putString(NVS_KEY_WIFI_PASS, pass);
  preferences.end();
  wifiSSID = ssid;
  wifiPassword = pass;
  Serial.printf("[CONFIG] WiFi credentials saved: %s\n", ssid);
}

// ─── BLE Provisioning Callbacks ────────────────────────────────────────────

class DeviceInfoCallback : public BLECharacteristicCallbacks {
  void onRead(BLECharacteristic* pCharacteristic) {
    String info = buildDeviceInfoJSON();
    pCharacteristic->setValue(info.c_str());
    Serial.printf("[BLE] Device info read: %s\n", info.c_str());
  }
};

class WiFiCredsCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String json = String(pCharacteristic->getValue().c_str());
    Serial.printf("[BLE] WiFi creds received: %s\n", json.c_str());

    StaticJsonDocument<256> doc;
    DeserializationError err = deserializeJson(doc, json);

    if (err) {
      Serial.printf("[BLE] JSON parse error: %s\n", err.c_str());
      return;
    }

    const char* ssid = doc["ssid"] | "";
    const char* pass = doc["password"] | "";

    if (strlen(ssid) == 0 || strlen(pass) == 0) {
      Serial.println("[BLE] Invalid credentials - ssid or password empty");
      return;
    }

    saveWiFiCredentials(ssid, pass);

    BLECharacteristic* pStatusChar =
        pCharacteristic->getService()->getCharacteristic(CHAR_UUID_PROV_STATUS);
    if (pStatusChar) {
      StaticJsonDocument<256> statusDoc;
      statusDoc["status"] = "connected";
      statusDoc["message"] = "WiFi credentials saved. Rebooting...";
      String statusJson;
      serializeJson(statusDoc, statusJson);
      pStatusChar->setValue(statusJson.c_str());
      pStatusChar->notify();
      delay(500);
    }

    Serial.println("[BLE] Rebooting to apply WiFi credentials...");
    ESP.restart();
  }
};

void startBLEProvisioning() {
  Serial.println("\n=== BLE Provisioning Mode ===");

  BLEDevice::init(getShortName().c_str());
  BLEServer* pServer = BLEDevice::createServer();
  BLEService* pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic* pDeviceInfoChar =
      pService->createCharacteristic(CHAR_UUID_DEVICE_INFO, BLECharacteristic::PROPERTY_READ);
  pDeviceInfoChar->setCallbacks(new DeviceInfoCallback());
  pDeviceInfoChar->setValue(buildDeviceInfoJSON().c_str());

  BLECharacteristic* pWifiCredsChar =
      pService->createCharacteristic(CHAR_UUID_WIFI_CREDS, BLECharacteristic::PROPERTY_WRITE);
  pWifiCredsChar->setCallbacks(new WiFiCredsCallback());

  BLECharacteristic* pProvStatusChar =
      pService->createCharacteristic(CHAR_UUID_PROV_STATUS,
          BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  pProvStatusChar->setValue("{\"status\":\"waiting\"}");

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.printf("Advertising as: %s\n", getShortName().c_str());
  Serial.printf("Service UUID: %s\n", SERVICE_UUID);
  Serial.println("Waiting for WiFi credentials via BLE...");
}

// ─── Setup ───────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);

  pinMode(LED_PIN, OUTPUT);
  pinMode(SOS_BUTTON_PIN, INPUT_PULLUP);

  Wire.begin(21, 22);
  mpu.initialize();
  if (!mpu.testConnection()) {
    Serial.println("MPU6050 connection failed!");
  } else {
    Serial.println("MPU6050 connected.");
  }

  // Load stored config (WiFi creds, device ID) from NVS
  bool hasStoredConfig = loadStoredConfig();

  if (hasStoredConfig) {
    if (connectWiFi()) {
      // WiFi success — normal operation
      connectFirebase();
      Firebase.RTDB.setBool(&fbdo, String("/devices/") + deviceId + "/sensors/online", true);
      Serial.println("\n=== ESP32 Guardian Firmware Started ===");
      Serial.printf("Device ID: %s\n", deviceId.c_str());
      Serial.printf("SOS Button Pin: GPIO %d (active LOW)\n", SOS_BUTTON_PIN);
      Serial.println("Ready for operation.");
      delay(2000);
      fetchGeofences();
      return;
    }
    Serial.println("Stored WiFi failed, entering provisioning mode...");
  } else {
    Serial.println("No stored WiFi credentials, entering provisioning mode...");
  }

  // Start BLE provisioning if WiFi failed or no creds stored
  provisioningMode = true;
  startBLEProvisioning();
}

// ─── Loop ────────────────────────────────────────────────────────────────────
void loop() {
  // In provisioning mode, only blink LED and wait for BLE connection
  if (provisioningMode) {
    bool ledState = (millis() % 2000 < 100);
    digitalWrite(LED_PIN, ledState ? HIGH : LOW);
    delay(10);
    return;
  }

  // Feed GPS
  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }

  // ── SOS Button (active LOW, press = falling edge HIGH→LOW) ──────────────
  // FIX: Debounce time reduced to 50ms so a normal quick press is detected
  // immediately. The old 500ms debounce was longer than a typical button tap,
  // which is why a long press was needed to register.
  bool currentButtonState = digitalRead(SOS_BUTTON_PIN);

  if (currentButtonState == LOW && lastButtonState == HIGH) {
    unsigned long now = millis();
    if (now - lastButtonPressTime > BUTTON_DEBOUNCE_MS) {
      Serial.println("\n>>> SOS BUTTON PRESSED <<<");
      lastSOSTime = now;        // FIX: record time so fall suppression kicks in
      lastButtonPressTime = now;
      triggerEmergency("SOS button pressed");
    }
  }
  lastButtonState = currentButtonState;

  // ── Non-blocking emergency LED flash ────────────────────────────────────
  // FIX: Replaced the blocking delay() LED loop in triggerEmergency() with
  // a non-blocking version here. The old loop blocked for ~2 seconds, which
  // caused the button press edge to be missed on release detection.
  if (isFlashingEmergency) {
    unsigned long now = millis();
    if (now - lastLedToggleTime >= 100) {
      emergencyLedOn = !emergencyLedOn;
      digitalWrite(LED_PIN, emergencyLedOn ? HIGH : LOW);
      lastLedToggleTime = now;
      emergencyLedFlashCount++;
      if (emergencyLedFlashCount >= 20) { // 10 on + 10 off = 10 blinks
        isFlashingEmergency = false;
        emergencyLedFlashCount = 0;
        digitalWrite(LED_PIN, LOW);
      }
    }
  }

  // Diagnostic print every 10s
  if (millis() - lastDiagnosticTime > DIAGNOSTIC_INTERVAL_MS) {
    Serial.printf("[STATUS] Button: %s | Emergency: %s | WiFi: %s\n",
      currentButtonState == LOW ? "PRESSED" : "Released",
      emergencyActive ? "YES" : "NO",
      WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected");
    lastDiagnosticTime = millis();
  }

  // Only run sensor updates on interval
  if (millis() - lastUpdateTime < UPDATE_INTERVAL_MS) return;
  lastUpdateTime = millis();

  // Read accelerometer
  int16_t ax, ay, az, gx, gy, gz;
  mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);

  float accelX = ax / 16384.0;
  float accelY = ay / 16384.0;
  float accelZ = az / 16384.0;
  float magnitude = sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);

  // ── Fall Detection ───────────────────────────────────────────────────────
  // FIX: Skip fall detection entirely for SOS_FALL_SUPPRESS_MS after an SOS
  // press. Pressing the button causes a physical jolt that spikes the
  // accelerometer above the threshold — without this guard, every SOS press
  // also logs a false fall alert.
  bool sosRecentlyPressed = (millis() - lastSOSTime) < SOS_FALL_SUPPRESS_MS;

  if (!sosRecentlyPressed &&
      magnitude > FALL_ACCEL_THRESHOLD &&
      millis() - lastFallTime > FALL_COOLDOWN_MS) {
    fallDetected = true;
    lastFallTime = millis();
    triggerEmergency("Fall detected by accelerometer");
    Serial.printf("FALL DETECTED! Magnitude: %.2f g\n", magnitude);
  }

  // Push sensor data
  pushSensorData(accelX, accelY, accelZ, fallDetected);

  // Check if emergency was cleared from app
  if (emergencyActive) {
    if (Firebase.RTDB.getBool(&fbdo, String("/devices/") + deviceId + "/emergency/active")) {
      bool isActive = fbdo.to<bool>();
      if (!isActive) {
        resetEmergency();
      }
    }
  }

  // Check geofences periodically
  if (millis() - lastGeofenceCheckTime > GEOFENCE_CHECK_INTERVAL_MS) {
    checkGeofences();
    lastGeofenceCheckTime = millis();
  }

  // Normal heartbeat LED blink (only when not doing emergency flash)
  if (!isFlashingEmergency) {
    digitalWrite(LED_PIN, !digitalRead(LED_PIN));
  }

  // Reset fall flag after cooldown
  if (fallDetected && millis() - lastFallTime > FALL_COOLDOWN_MS) {
    fallDetected = false;
  }
}

// ─── Push Sensor Data ─────────────────────────────────────────────────────────
void pushSensorData(float ax, float ay, float az, bool fall) {
  String basePath = String("/devices/") + deviceId + "/sensors/";

  if (gps.location.isUpdated()) {
    Firebase.RTDB.setFloat(&fbdo, basePath + "gps/lat", gps.location.lat());
    Firebase.RTDB.setFloat(&fbdo, basePath + "gps/lng", gps.location.lng());
  }

  Firebase.RTDB.setFloat(&fbdo, basePath + "accelerometer/x", ax);
  Firebase.RTDB.setFloat(&fbdo, basePath + "accelerometer/y", ay);
  Firebase.RTDB.setFloat(&fbdo, basePath + "accelerometer/z", az);

  Firebase.RTDB.setBool(&fbdo, basePath + "fallDetected", fall);
  Firebase.RTDB.setBool(&fbdo, basePath + "online", true);
  Firebase.RTDB.setTimestamp(&fbdo, basePath + "timestamp");

  Serial.printf("Pushed → Accel: %.2f,%.2f,%.2f | GPS: %.6f,%.6f | Fall: %s\n",
    ax, ay, az,
    gps.location.lat(), gps.location.lng(),
    fall ? "YES" : "NO");
}

// ─── Trigger Emergency ────────────────────────────────────────────────────────
void triggerEmergency(String reason) {
  if (emergencyActive) {
    Serial.println("Emergency already active, ignoring duplicate trigger.");
    return;
  }

  String path = String("/devices/") + deviceId + "/emergency/";

  bool success = true;
  success = Firebase.RTDB.setBool(&fbdo, path + "active", true) && success;
  success = Firebase.RTDB.setString(&fbdo, path + "reason", reason) && success;
  success = Firebase.RTDB.setTimestamp(&fbdo, path + "triggeredAt") && success;

  if (gps.location.isValid()) {
    Firebase.RTDB.setFloat(&fbdo, path + "lat", gps.location.lat());
    Firebase.RTDB.setFloat(&fbdo, path + "lng", gps.location.lng());
    Serial.printf("GPS: %.6f, %.6f\n", gps.location.lat(), gps.location.lng());
  }

  emergencyActive = true;

  Serial.println("\n========================================");
  Serial.println("EMERGENCY TRIGGERED!");
  Serial.println("Reason: " + reason);
  Serial.println("Status: " + String(success ? "Sent to Firebase" : "Firebase error"));
  Serial.println("========================================\n");

  // FIX: Start non-blocking LED flash instead of blocking delay() loop
  isFlashingEmergency = true;
  emergencyLedFlashCount = 0;
  lastLedToggleTime = millis();
}

// ─── Reset Emergency ──────────────────────────────────────────────────────────
void resetEmergency() {
  if (emergencyActive) {
    emergencyActive = false;
    fallDetected = false;
    Serial.println("\n>>> Emergency cleared from app <<<\n");
  }
}

// ─── WiFi Connection ──────────────────────────────────────────────────────────
bool connectWiFi() {
  if (wifiSSID.length() == 0) {
    Serial.println("WiFi: No stored credentials.");
    return false;
  }

  Serial.printf("Connecting to WiFi: %s\n", wifiSSID.c_str());
  WiFi.begin(wifiSSID.c_str(), wifiPassword.c_str());

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - start > WIFI_CONNECT_TIMEOUT_MS) {
      Serial.println("\nWiFi: Connection timeout.");
      return false;
    }
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi connected: " + WiFi.localIP().toString());
  return true;
}

// ─── Firebase Connection ──────────────────────────────────────────────────────
void connectFirebase() {
  fbConfig.host = FIREBASE_HOST;
  fbConfig.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&fbConfig, &fbAuth);
  Firebase.reconnectWiFi(true);
  Serial.println("Firebase connected.");
}

// ─── Geofence Functions ───────────────────────────────────────────────────────

void fetchGeofences() {
  if (!gps.location.isValid()) {
    Serial.println("[GEOFENCE] Waiting for GPS fix...");
    return;
  }

  String geofencePath = String("/devices/") + deviceId + "/geofences";

  if (Firebase.RTDB.getJSON(&fbdo, geofencePath)) {
    DynamicJsonDocument doc(4096);
    deserializeJson(doc, fbdo.to<const char*>());

    geofenceCount = 0;

    if (doc.is<JsonArray>()) {
      JsonArray arr = doc.as<JsonArray>();

      for (size_t i = 0; i < arr.size() && i < MAX_GEOFENCES; i++) {
        JsonObject obj = arr[i].as<JsonObject>();

        if (!obj.isNull()) {
          strcpy(geofences[geofenceCount].id, obj["id"] | "unknown");
          strcpy(geofences[geofenceCount].name, obj["name"] | "unnamed");
          geofences[geofenceCount].latitude = obj["lat"] | 0.0;
          geofences[geofenceCount].longitude = obj["lng"] | 0.0;
          geofences[geofenceCount].radiusMeters = obj["radius"] | 500.0;
          geofenceCount++;
        }
      }
    }

    Serial.printf("[GEOFENCE] Fetched %d geofences from Firebase\n", geofenceCount);
  } else {
    Serial.printf("[GEOFENCE] No geofences found or error: %s\n", fbdo.errorReason().c_str());
    geofenceCount = 0;
  }
}

float calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const float EARTH_RADIUS_M = 6371000.0;

  double dlat = (lat2 - lat1) * 0.0174533;
  double dlon = (lon2 - lon1) * 0.0174533;

  double a = sin(dlat / 2.0) * sin(dlat / 2.0)
           + cos(lat1 * 0.0174533) * cos(lat2 * 0.0174533)
           * sin(dlon / 2.0) * sin(dlon / 2.0);

  double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
  return EARTH_RADIUS_M * c;
}

void checkGeofences() {
  if (geofenceCount == 0) {
    fetchGeofences();
    return;
  }

  if (!gps.location.isValid()) return;

  double currentLat = gps.location.lat();
  double currentLng = gps.location.lng();

  Serial.printf("\n[GEOFENCE CHECK] Location: %.6f, %.6f\n", currentLat, currentLng);

  for (int i = 0; i < geofenceCount; i++) {
    float distance = calculateDistance(
        currentLat, currentLng,
        geofences[i].latitude, geofences[i].longitude);

    bool isInside = distance <= geofences[i].radiusMeters;
    bool wasInside = lastGeofenceStatus[i];

    if (isInside != wasInside) {
      String violationType = isInside ? "entered" : "exited";
      Serial.printf("[GEOFENCE] Zone '%s': %s (distance: %.1f m)\n",
          geofences[i].name, violationType.c_str(), distance);

      logGeofenceViolation(
          geofences[i].id, geofences[i].name,
          violationType, currentLat, currentLng, distance);

      lastGeofenceStatus[i] = isInside;
    }
  }

  Serial.println("[GEOFENCE CHECK] Complete\n");
}

void logGeofenceViolation(
    const char* geofenceId,
    const char* geofenceName,
    const String& type,
    double lat,
    double lng,
    float distance) {

  String path = String("/devices/") + deviceId + "/geofence_violations/";
  String tsKey = String(millis()); // unique key only, not stored as a time value
  path += tsKey;

  FirebaseJson json;
  json.set("geofenceId", geofenceId);
  json.set("name", geofenceName);
  json.set("type", type.c_str());
  json.set("lat", lat);
  json.set("lng", lng);
  json.set("distance", distance);
  json.set("timestamp/.sv", "timestamp");

  if (Firebase.RTDB.setJSON(&fbdo, path, &json)) {
    Serial.println("Geofence violation logged to Firebase");
  } else {
    Serial.printf("Failed to log violation: %s\n", fbdo.errorReason().c_str());
  }
}
