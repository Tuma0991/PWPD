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

// ─── Update Interval ─────────────────────────────────────────────────────────
#define UPDATE_INTERVAL_MS     2000  // Push data to Firebase every 2s

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
const unsigned long BUTTON_DEBOUNCE_MS = 500; // 500ms debounce
const unsigned long DIAGNOSTIC_INTERVAL_MS = 10000; // Print diagnostic every 10s

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
