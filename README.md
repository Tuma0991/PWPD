# 🛡️ Guardian — IoT Wearable Protection App

A Flutter mobile application for your **ESP32-based wearable safety device** capstone project.
Connects to Firebase Realtime Database to receive live sensor data, GPS location, fall detection alerts, and manage emergency contacts.

---

## 📁 Project Structure

```
guardian_app/
├── lib/
│   ├── main.dart                    # Entry point + auth routing
│   ├── theme.dart                   # Blue & white color theme
│   ├── models/
│   │   ├── device_data.dart         # ESP32 sensor data model
│   │   └── contact_model.dart       # Emergency contact model
│   ├── services/
│   │   └── firebase_service.dart    # Firebase Auth + RTDB + Firestore
│   └── screens/
│       ├── auth_screen.dart         # Login / Register
│       ├── home_screen.dart         # Dashboard with live status cards
│       ├── map_screen.dart          # Live GPS map (OpenStreetMap)
│       ├── fall_detection_screen.dart  # Accelerometer + fall status
│       ├── alerts_screen.dart       # Alert history log
│       └── contacts_screen.dart     # Emergency contacts manager
└── esp32_firmware/
esp32_firmware/
    └── guardian_firmware/            # Arduino C++ project for ESP32
```

---

## 🚀 Setup Guide

### Step 1 — Firebase Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project (e.g., `guardian-capstone`)
3. Enable these services:
   - **Authentication** → Email/Password
   - **Realtime Database** → Start in test mode
   - **Firestore** → Start in test mode

4. Download `google-services.json` (Android) and place it in `android/app/`

5. Set your **Realtime Database rules**:
```json
{
  "rules": {
    "devices": {
      "$deviceId": {
        ".read": "auth != null",
        ".write": "auth != null"
      }
    }
  }
}
```

---

### Step 2 — Map Setup (No API Key Needed)

The app uses **OpenStreetMap** with `flutter_map` — completely free, no API key required. No setup needed; maps work out of the box.

---

### Step 3 — Android Permissions

In `android/app/src/main/AndroidManifest.xml`, add:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.CALL_PHONE"/>
```

---

### Step 4 — Install Flutter Dependencies

```bash
flutter pub get
```

---

### Step 5 — Run the App

```bash
flutter run
```

---

## 🔌 ESP32 Firebase Data Structure

The ESP32 pushes data to Firebase Realtime Database at this path:

```
/devices/esp32_device_1/
├── sensors/
│   ├── gps/
│   │   ├── lat: 10.3157
│   │   └── lng: 123.8854
│   ├── accelerometer/
│   │   ├── x: 0.12
│   │   ├── y: -0.03
│   │   └── z: 9.81
│   ├── fallDetected: false
│   ├── online: true
│   └── timestamp: 1234567890
└── emergency/
    ├── active: false
    ├── reason: "Fall detected"
    ├── lat: 10.3157
    ├── lng: 123.8854
    └── triggeredAt: 1234567890
```

---

## 🔧 ESP32 Firmware Setup

1. Open `esp32_firmware/guardian_firmware.ino` in Arduino IDE

2. Install these libraries via Library Manager:
   - `Firebase ESP32 Client` by mobizt
   - `TinyGPS++` by Mikal Hart
   - `MPU6050` by Electronic Cats
   - `ArduinoJson` by Benoit Blanchon

3. Update these values in the firmware:
```cpp
#define WIFI_SSID       "YOUR_WIFI_SSID"
#define WIFI_PASSWORD   "YOUR_WIFI_PASSWORD"
#define FIREBASE_HOST   "YOUR_PROJECT_ID.firebaseio.com"
#define FIREBASE_AUTH   "YOUR_DATABASE_SECRET"
```

4. Upload to ESP32 → Open Serial Monitor → Should show "Firebase connected"

---

## 📱 App Features

| Screen | Feature |
|--------|---------|
| **Login / Register** | Firebase Email Auth |
| **Dashboard** | Live device status, emergency banner |
| **Map** | Real-time GPS tracking via OpenStreetMap |
| **Sensors** | Live accelerometer bars, fall status |
| **Alerts** | History of all emergency events |
| **Contacts** | Add/edit/delete emergency contacts, tap to call |

---

## ⚡ How Data Flows

```
ESP32 (MPU6050 + GPS)
        │
        │  WiFi → HTTP
        ▼
Firebase Realtime Database
        │
        │  Stream listener
        ▼
Flutter App (live updates, no refresh needed)
        │
        │  Alert triggered
        ▼
Firestore (alert logged) + Push Notification
```

---

## 🛠️ Customization

- **Change Device ID**: Update `_deviceId` in `home_screen.dart` and `DEVICE_ID` in firmware
- **Fall Threshold**: Adjust `FALL_ACCEL_THRESHOLD` in firmware (default: 2.5g)
- **Update Frequency**: Adjust `UPDATE_INTERVAL_MS` (default: 2000ms = 2 seconds)
- **App Colors**: Edit `lib/theme.dart`

---

## 👨‍💻 Tech Stack

- **Flutter** (Dart) — Mobile App
- **Firebase Auth** — User authentication
- **Firebase Realtime Database** — Live ESP32 sensor data
- **Cloud Firestore** — Alert history & contacts
- **flutter_map + OpenStreetMap** — Live GPS map (free, no API key)
- **ESP32** — Microcontroller
- **MPU6050** — Accelerometer (fall detection)
- **NEO-6M GPS** — Location tracking
