# 🛡️ Guardian App - Crash Fix & ESP32 Connection Guide

## ✅ What Was Fixed Today

### 1. **Google Maps Crash** (Fixed)
   - **Problem**: App crashes when you open the Map screen
   - **Cause**: Missing Google Maps API key in Android configuration
   - **Solution**: Added proper metadata tag to `AndroidManifest.xml`
   - **What you need to do**: Get a real Google Maps API key and add it

### 2. **Missing Permissions** (Fixed)
   - **Problem**: App might crash on devices due to missing location/internet permissions
   - **Solution**: Added required permissions to `AndroidManifest.xml`:
     - `ACCESS_FINE_LOCATION` (precise GPS)
     - `ACCESS_COARSE_LOCATION` (approximate location)
     - `INTERNET` (Firebase connection)
     - `ACCESS_NETWORK_STATE` (network detection)

---

## 🚀 Quick Start (5 Steps)

### **STEP 1: Get Google Maps API Key** ⓵ CRITICAL ⓵

Without this, the Map screen will crash!

1. Go to https://console.cloud.google.com/
2. Create a new project (name it "Guardian" or similar)
3. Search for and enable **"Maps SDK for Android"**
4. Go to **Credentials** → **Create API Key** → **Android**
5. Find your app's SHA-1 fingerprint:
   ```powershell
   # Windows PowerShell
   keytool -list -v -keystore $env:USERPROFILE\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```
   Look for "SHA1:" in the output

6. Add this SHA-1 fingerprint to the API key restrictions
7. **Copy the API key**

### **STEP 2: Configure ESP32 Firmware**

1. Open: `esp32_firmware/guardian_firmware.ino`
2. Update lines 29-33:
   ```cpp
   #define WIFI_SSID           "YourWiFiName"
   #define WIFI_PASSWORD       "YourWiFiPassword"
   #define FIREBASE_HOST       "your-project.firebaseio.com"
   #define FIREBASE_AUTH       "your-database-secret"
   #define DEVICE_ID           "esp32_device_1"
   ```

3. **Get Firebase Host & Auth Token**:
   - Go to Firebase Console → Your Project → **Realtime Database**
   - The URL shows the host (e.g., `guardian-abc123.firebaseio.com`)
   - Click the Settings ⚙️ icon → **Database secrets** tab
   - Copy the token shown there

4. Upload to ESP32 using Arduino IDE (115200 baud rate)

### **STEP 4: Set Firebase RTDB Security Rules**

1. Firebase Console → Realtime Database → **Rules** tab
2. Replace all rules with:
   ```json
   {
     "rules": {
       "devices": {
         "$deviceId": {
           ".read": true,
           ".write": true,
           "sensors": {},
           "emergency": {}
         }
       }
     }
   }
   ```
3. Click **Publish**

### **STEP 5: Test Everything**

```bash
cd d:\PWPD\pwpd
flutter clean
flutter pub get
flutter run
```

Test each screen:
- **Dashboard** → Should show device online/offline status
- **Map** → Should show device location (if GPS has lock)
- **Sensors** → Should show accelerometer data
- **Alerts** → Should show any fall alerts
- **Contacts** → Should allow adding emergency contacts

---

## 📱 How the App Connects to ESP32

The connection happens through **Firebase Realtime Database** (NOT direct WiFi):

```
┌────────────────────────────┐
│   ESP32 + Sensors         │
│ (WiFi Connected)          │
└──────────────┬─────────────┘
               │ Sends sensor data every 2 seconds
               │ via WiFi to Firebase
               ▼
    ┌─────────────────────────────├─────────────┐
    │  Firebase Realtime Database │             │
    │  /devices/esp32_device_1/   │             │
    │  ├── sensors                │             │
    │  │   ├── gps.lat            │             │
    │  │   ├── gps.lng            │             │
    │  │   ├── accelerometer.x/y/z│             │
    │  │   └── timestamp          │             │
    │  ├── emergency              │             │
    │  │   └── active: true/false │             │
    │  └── online: true/false     │    🌐      │
    └─────────────────────────────├─────────────┘
                 │
                 │ App listens to these streams
                 │ in real-time
                 ▼
        ┌──────────────────┐
        │  Your Phone      │
        │  Flutter App     │
        │  Shows live data │
        └──────────────────┘
```

**Key Points:**
- ✅ The app automatically connects to Firebase
- ✅ The app looks for device ID `esp32_device_1`
- ✅ The ESP32 must push data to the same device ID path
- ✅ Everything is real-time (changes show instantly)

---

## 🔧 Android Manifest Changes Made

Here's what was added to fix the crashes:

**BEFORE** (broken):
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="pwpd" ...>
```

**AFTER** (fixed):
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Permissions added -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <!-- Maps: Using OpenStreetMap (free, no API key required) -->
```

---

## 🆘 Troubleshooting

| Problem | Solution |
|---------|----------|
| **Map screen not displaying** | 1. Check internet connection (tiles download from OpenStreetMap) <br/> 2. Verify GPS permissions are granted <br/> 3. Try restarting the app |
| **"Device is offline" on Dashboard** | 1. Check ESP32 WiFi SSID/password are correct <br/> 2. Check Firebase credentials correct <br/> 3. Check ESP32 has internet (ping 8.8.8.8) <br/> 4. Check Firebase RTDB rules allow writes |
| **Map shows GPS 0.0, 0.0** | 1. ESP32 GPS needs 5-10 minutes outdoors for lock <br/> 2. Check GPS module wiring (RX=pin 16, TX=pin 17) <br/> 3. Monitor ESP32 serial output (Tools → Serial Monitor) |
| **"Can't sign in" to app** | 1. Check Firebase has users created <br/> 2. Check Email/Password authentication is enabled <br/> 3. Check phone has internet connection |
| **Fall detection triggers too often** | 1. Edit ESP32: `#define FALL_ACCEL_THRESHOLD 3.0` (increase to 3.0) <br/> 2. Test with gentle shakes, not hard impacts |

---

## 📁 Files Modified/Created

✅ **Modified:**
- `android/app/src/main/AndroidManifest.xml` — Added permissions & API key placeholder

✅ **Created:**
- `SETUP_GUIDE.md` — Complete step-by-step setup instructions
- `ESP32_CONFIG_TEMPLATE.h` — Configuration template with explanations

---

## 🎯 App Architecture Overview

```
Guardian (Flutter App)
│
├── Authentication
│   ├── login/register (Firebase Auth)
│   └── auto-login if already signed in
│
├── Real-time Device Monitoring (Firebase RTDB)
│   ├── Dashboard → Shows device status & sensor readings
│   ├── Map → Live GPS location tracking
│   ├── Sensors → Accelerometer data & fall detection
│   └── Alerts → Alert history (Firestore)
│
├── Emergency Contact Management (Firestore)
│   └── Contacts → Add/edit/delete emergency numbers
│
└── ESP32 → Firebase Bridge
    ├── Reads sensors (GPS, Accelerometer)
    ├── Detects falls
    ├── Sends data to Firebase RTDB
    └── Receives commands from app
```

---

## 📚 Additional Resources

- **Google Maps API Setup**: https://developers.google.com/maps/documentation/android-sdk/start
- **Firebase Console**: https://console.firebase.google.com/
- **Flutter Documentation**: https://flutter.dev/docs
- **ESP32 Arduino IDE Setup**: https://docs.espressif.com/projects/arduino-esp32/en/latest/

---

## ❓ Feel Free to Ask

If you need help with:
- Getting the Google Maps API key
- Uploading ESP32 code
- Setting up Firebase
- Debugging any errors

Just let me know! This guide has all the major steps covered. 🚀
