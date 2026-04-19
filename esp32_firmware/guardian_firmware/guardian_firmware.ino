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

// ─── WiFi & Firebase Config ───────────────────────────────────────────────────
#define WIFI_SSID       "GlobeAtHome_f4850"
#define WIFI_PASSWORD   "pd6fpWbj"
#define FIREBASE_HOST   "https://pwpd-5e580-default-rtdb.firebaseio.com"
#define FIREBASE_AUTH   "sr2NtPXykxRmnrVuYu4ilmFodKHDkLNHKRFe3AwG"
#define DEVICE_ID       "esp32_device_1"

// ─── Pin Config ───────────────────────────────────────────────────────────────
#define GPS_RX_PIN      16    // ESP32 RX2
#define GPS_TX_PIN      17    // ESP32 TX2
#define SOS_BUTTON_PIN  4     // Emergency button
#define LED_PIN         2     // Built-in LED

// ─── Fall Detection Threshold ─────────────────────────────────────────────────
// Increase threshold to reduce false positives (default: 2.5g impact)
#define FALL_ACCEL_THRESHOLD   2.5   // in g-force units
#define FALL_COOLDOWN_MS       5000  // 5 seconds before re-detecting

// ─── Geofence Config ──────────────────────────────────────────────────────────
#define GEOFENCE_CHECK_INTERVAL_MS 30000  // Check geofences every 30 seconds
#define MAX_GEOFENCES 10                   // Max number of geofences per device

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
const unsigned long BUTTON_DEBOUNCE_MS = 500; // 500ms debounce
const unsigned long DIAGNOSTIC_INTERVAL_MS = 10000; // Print diagnostic every 10s

// Geofence state
Geofence geofences[MAX_GEOFENCES];
int geofenceCount = 0;
bool lastGeofenceStatus[MAX_GEOFENCES] = {false}; // Track previous state

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

  connectWiFi();
  connectFirebase();

  // Mark device as online
  Firebase.RTDB.setBool(&fbdo, String("/devices/") + DEVICE_ID + "/sensors/online", true);
  Serial.println("\n=== ESP32 Guardian Firmware Started ===");
  Serial.printf("SOS Button Pin: GPIO %d (active LOW)\n", SOS_BUTTON_PIN);
  Serial.println("Ready for operation.");
  
  // Fetch initial geofences
  delay(2000); // Wait for GPS to initialize
  fetchGeofences();
}

// ─── Loop ────────────────────────────────────────────────────────────────────
void loop() {
  // Feed GPS
  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }

  // Check SOS button (active LOW) with non-blocking debounce
  bool currentButtonState = digitalRead(SOS_BUTTON_PIN);
  
  // Detect button press (transition from HIGH to LOW)
  if (currentButtonState == LOW && lastButtonState == HIGH) {
    // Button just pressed
    unsigned long now = millis();
    if (now - lastButtonPressTime > BUTTON_DEBOUNCE_MS) {
      Serial.println("\n>>> SOS BUTTON PRESSED <<<");
      triggerEmergency("SOS button pressed");
      lastButtonPressTime = now;
    }
  }
  lastButtonState = currentButtonState;

  // Print diagnostic status every 10 seconds
  if (millis() - lastDiagnosticTime > DIAGNOSTIC_INTERVAL_MS) {
    Serial.printf("[STATUS] Button State: %s | Emergency Active: %s | WiFi: %s\n",
      currentButtonState == LOW ? "PRESSED" : "Released",
      emergencyActive ? "YES" : "NO",
      WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected");
    lastDiagnosticTime = millis();
  }

  // Only update on interval
  if (millis() - lastUpdateTime < UPDATE_INTERVAL_MS) return;
  lastUpdateTime = millis();

  // Read accelerometer
  int16_t ax, ay, az, gx, gy, gz;
  mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);

  // Convert raw to g-force (±2g range → 16384 LSB/g)
  float accelX = ax / 16384.0;
  float accelY = ay / 16384.0;
  float accelZ = az / 16384.0;
  float magnitude = sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);

  // Fall detection
  if (magnitude > FALL_ACCEL_THRESHOLD &&
      millis() - lastFallTime > FALL_COOLDOWN_MS) {
    fallDetected = true;
    lastFallTime = millis();
    triggerEmergency("Fall detected by accelerometer");
    Serial.printf("FALL DETECTED! Magnitude: %.2f g\n", magnitude);
  }

  // Push sensor data to Firebase
  pushSensorData(accelX, accelY, accelZ, fallDetected);

  // Check if emergency was cleared from app
  if (emergencyActive) {
    if (Firebase.RTDB.getBool(&fbdo, String("/devices/") + DEVICE_ID + "/emergency/active")) {
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

  // Blink LED
  digitalWrite(LED_PIN, !digitalRead(LED_PIN));

  // Reset fall flag after cooldown
  if (fallDetected && millis() - lastFallTime > FALL_COOLDOWN_MS) {
    fallDetected = false;
  }
}

// ─── Push Sensor Data ─────────────────────────────────────────────────────────
void pushSensorData(float ax, float ay, float az, bool fall) {
  String basePath = String("/devices/") + DEVICE_ID + "/sensors/";

  // GPS
  if (gps.location.isUpdated()) {
    Firebase.RTDB.setFloat(&fbdo, basePath + "gps/lat", gps.location.lat());
    Firebase.RTDB.setFloat(&fbdo, basePath + "gps/lng", gps.location.lng());
  }

  // Accelerometer
  Firebase.RTDB.setFloat(&fbdo, basePath + "accelerometer/x", ax);
  Firebase.RTDB.setFloat(&fbdo, basePath + "accelerometer/y", ay);
  Firebase.RTDB.setFloat(&fbdo, basePath + "accelerometer/z", az);

  // Status
  Firebase.RTDB.setBool(&fbdo, basePath + "fallDetected", fall);
  Firebase.RTDB.setBool(&fbdo, basePath + "online", true);
  Firebase.RTDB.setInt(&fbdo, basePath + "timestamp", millis());

  Serial.printf("Pushed → Accel: %.2f,%.2f,%.2f | GPS: %.6f,%.6f | Fall: %s\n",
    ax, ay, az,
    gps.location.lat(), gps.location.lng(),
    fall ? "YES" : "NO");
}

// ─── Trigger Emergency ────────────────────────────────────────────────────────
void triggerEmergency(String reason) {
  if (emergencyActive) {
    Serial.println("Emergency already active, ignoring duplicate trigger.");
    return; // already active
  }

  String path = String("/devices/") + DEVICE_ID + "/emergency/";
  
  // Send to Firebase
  bool success = true;
  success = Firebase.RTDB.setBool(&fbdo, path + "active", true) && success;
  success = Firebase.RTDB.setString(&fbdo, path + "reason", reason) && success;
  success = Firebase.RTDB.setInt(&fbdo, path + "triggeredAt", millis()) && success;

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

  // Flash LED rapidly
  for (int i = 0; i < 10; i++) {
    digitalWrite(LED_PIN, HIGH); delay(100);
    digitalWrite(LED_PIN, LOW);  delay(100);
  }
}

// ─── Reset Emergency (called when cleared from app) ────────────────────────────
void resetEmergency() {
  if (emergencyActive) {
    emergencyActive = false;
    fallDetected = false;
    Serial.println("\n>>> Emergency cleared from app <<<\n");
  }
}

// ─── WiFi Connection ──────────────────────────────────────────────────────────
void connectWiFi() {
  Serial.print("Connecting to WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected: " + WiFi.localIP().toString());
}

// ─── Firebase Connection ──────────────────────────────────────────────────────
void connectFirebase() {
  fbConfig.host = FIREBASE_HOST;
  fbConfig.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&fbConfig, &fbAuth);
  Firebase.reconnectWiFi(true);
  Serial.println("Firebase connected.");
}

// ─── Geofence Functions ────────────────────────────────────────────────────────

/// Fetch geofences from Firebase and update local array
void fetchGeofences() {
  if (!gps.location.isValid()) {
    Serial.println("[GEOFENCE] Waiting for GPS fix...");
    return;
  }

  // Fetch geofences from Firebase RTDB
  String geofencePath = String("/devices/") + DEVICE_ID + "/geofences";
  
  if (Firebase.RTDB.getJSON(&fbdo, geofencePath)) {
    // fbdo.jsonObject() contains the geofences array
    // We'll iterate through the JSON object which should be an array
    DynamicJsonDocument doc(4096);
    deserializeJson(doc, fbdo.to<const char*>());
    
    geofenceCount = 0;
    
    // Check if it's an array
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

/// Calculate distance between two GPS points using Haversine formula
/// Returns distance in meters
float calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const float EARTH_RADIUS_M = 6371000.0; // Earth's radius in meters

  // Convert to radians
  double dlat = (lat2 - lat1) * 0.0174533; // PI/180
  double dlon = (lon2 - lon1) * 0.0174533;

  double a = sin(dlat / 2.0) * sin(dlat / 2.0)
           + cos(lat1 * 0.0174533) * cos(lat2 * 0.0174533)
           * sin(dlon / 2.0) * sin(dlon / 2.0);

  double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
  return EARTH_RADIUS_M * c;
}

/// Check geofence boundaries and report violations
void checkGeofences() {
  if (geofenceCount == 0) {
    fetchGeofences();
    return;
  }

  if (!gps.location.isValid()) {
    return; // No GPS fix yet
  }

  double currentLat = gps.location.lat();
  double currentLng = gps.location.lng();

  Serial.printf("\n[GEOFENCE CHECK] Location: %.6f, %.6f\n", currentLat, currentLng);

  for (int i = 0; i < geofenceCount; i++) {
    float distance = calculateDistance(
        currentLat,
        currentLng,
        geofences[i].latitude,
        geofences[i].longitude
    );

    bool isInside = distance <= geofences[i].radiusMeters;
    bool wasInside = lastGeofenceStatus[i];

    // Detect state change
    if (isInside != wasInside) {
      String violationType = isInside ? "entered" : "exited";
      Serial.printf("[GEOFENCE] Zone '%s': %s (distance: %.1f m)\n",
          geofences[i].name, violationType.c_str(), distance);

      // Log violation to Firebase
      logGeofenceViolation(
          geofences[i].id,
          geofences[i].name,
          violationType,
          currentLat,
          currentLng,
          distance
      );

      lastGeofenceStatus[i] = isInside;
    }
  }

  Serial.println("[GEOFENCE CHECK] Complete\n");
}

/// Log geofence violation to Firebase
void logGeofenceViolation(
    const char* geofenceId,
    const char* geofenceName,
    const String& type,
    double lat,
    double lng,
    float distance) {
  
  String path = String("/devices/") + DEVICE_ID + "/geofence_violations/";
  String timestamp = String(millis());
  path += timestamp;

  FirebaseJson json;
  json.set("geofenceId", geofenceId);
  json.set("name", geofenceName);
  json.set("type", type.c_str());
  json.set("lat", lat);
  json.set("lng", lng);
  json.set("distance", distance);
  json.set("timestamp", millis());

  if (Firebase.RTDB.setJSON(&fbdo, path, &json)) {
    Serial.println("Geofence violation logged to Firebase");
  } else {
    Serial.printf("Failed to log violation: %s\n", fbdo.errorReason().c_str());
  }
}
