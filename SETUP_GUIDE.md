# Guardian ESP32 Wearable App - Complete Setup Guide

## 🔧 What Was Configured

✅ **Maps Setup** — Using free OpenStreetMap (no API key required)  
✅ **Added required permissions** — Location, Internet, Network access  

---

## 📋 Complete Setup Checklist

### **STEP 1: Maps Configuration (No Setup Required!)**

The app uses **OpenStreetMap** with flutter_map, which is completely free and requires no API key.

✅ Maps are configured and ready to use  
✅ No sign-ups, payments, or API keys needed  
✅ Location tracking works automatically with GPS data from ESP32

### **STEP 2: Configure ESP32 Firmware**

The ESP32 needs WiFi and Firebase credentials to send data to your app.

#### A. Update WiFi & Firebase Config

Edit `esp32_firmware/guardian_firmware.ino` and update these lines (around line 29-33):

```cpp
#define WIFI_SSID           "YOUR_WIFI_SSID"              // ← Change this
#define WIFI_PASSWORD       "YOUR_WIFI_PASSWORD"          // ← Change this
#define FIREBASE_HOST       "YOUR_PROJECT_ID.firebaseio.com"  // ← Change this
#define FIREBASE_AUTH       "YOUR_LONG_SECRET_TOKEN"      // ← Change this (get from Firebase)
#define DEVICE_ID           "esp32_device_1"              // Keep this or change to match app config
```

#### B. Get Firebase Real-Time Database Secret Token

1. Go to **Firebase Console** → Your Project → **Database** (Realtime Database)
2. Click the **Settings** icon (gear icon) → **Database secrets**
3. Copy the token and paste it in `FIREBASE_AUTH`

#### C. Upload to ESP32

1. Use Arduino IDE or PlatformIO
2. Install required libraries (already in code comments):
   - `Firebase ESP32 Client by mobizt`
   - `TinyGPS++ by Mikal Hart`
   - `MPU6050 by Electronic Cats`
   - `ArduinoJson by Benoit Blanchon`

3. Select board: `ESP32 Dev Module` (or your variant)
4. Set baud rate: `115200`
5. Upload the sketch

### **STEP 3: Set Up Firebase Realtime Database (RTDB) Rules**

The app reads sensor data from Firebase RTDB. You need to set proper rules.

1. Go to **Firebase Console** → **Realtime Database** → **Rules**
2. Replace the default rules with:

```json
{
  "rules": {
    "devices": {
      "$deviceId": {
        ".read": true,
        ".write": "$deviceId === auth.uid || root.child('admins').child(auth.uid).exists()",
        "sensors": {
          ".read": true,
          ".write": true
        },
        "emergency": {
          ".read": true,
          ".write": true,
          "active": {},
          "clearedAt": {}
        }
      }
    }
  }
}
```

3. Click **Publish**

### **STEP 4: Create Initial Test Data (Optional but Recommended)**

To test the app without waiting for ESP32 to send data:

1. In Firebase Console → **Realtime Database**
2. Click the `+` button to add data
3. Key: `devices` → Click `+` → Add key: `esp32_device_1` → Click `+` → Add key: `sensors`
4. Add these fields:
```json
{
  "gps": {
    "lat": 10.3157,
    "lng": 123.8854
  },
  "accelerometer": {
    "x": 0.5,
    "y": 1.2,
    "z": 9.8
  },
  "fallDetected": false,
  "timestamp": 1234567890,
  "online": false
}
```

5. Also add `emergency` node:
```json
{
  "active": false
}
```

### **STEP 5: Test the App**

```bash
cd d:\PWPD\pwpd
flutter pub get
flutter run
```

**Test each screen:**
- ✅ Dashboard → Should show device data from Firebase
- ✅ Map → Should show device location (uses free OpenStreetMap tiles)
- ✅ Sensors → Should show accelerometer data
- ✅ Alerts → Should show alert history
- ✅ Contacts → Should allow adding emergency contacts

---

## 🔌 How ESP32 Connects to the App

```
┌─────────────────────────────────────────────┐
│         ESP32 Device                        │
│  (WiFi: Your_SSID)                         │
│  (Reads: MPU6050, GPS)                     │
└────────────────┬────────────────────────────┘
                 │ (Sends sensor data)
                 │ WiFi/Internet
                 ▼
    ┌────────────────────────────┐
    │  Firebase Realtime DB      │
    │  /devices/esp32_device_1   │
    │  ├── sensors (GPS, accel)  │
    │  ├── emergency (alert)     │
    │  └── ...                   │
    └────────────┬───────────────┘
                 │ (Listens for changes)
                 │ WiFi/Internet
                 ▼
        ┌──────────────────┐
        │  Flutter Mobile  │
        │      App         │
        │   (this phone)   │
        └──────────────────┘
```

**Key Points:**
- **Device ID must match**: App looks for `esp32_device_1` in Firebase
- **Firebase is the hub**: All communication goes through RTDB
- **No direct device connection**: ESP32 and phone don't communicate directly
- **Real-time updates**: StreamBuilder listens to RTDB for live updates

---

## 🆘 Troubleshooting

### **"Map screen is blank or not loading"**
→ Check internet connection. OpenStreetMap tiles require network access. No API key needed.

### **"Device is offline / no data showing"**
→ Check these:
1. ESP32 WiFi credentials correct (`WIFI_SSID` / `WIFI_PASSWORD`)
2. Firebase credentials correct (`FIREBASE_HOST` / `FIREBASE_AUTH`)
3. ESP32 has internet connection
4. Firebase RTDB security rules allow reads/writes
5. Device ID in ESP32 (`DEVICE_ID`) matches app (`esp32_device_1`)

### **"Can't log in to app"**
→ Check:
1. Firebase Authentication is enabled (Email/Password method)
2. User account exists in Firebase Console → Authentication
3. Internet connection on phone
4. Firebase iOS/Android configuration files are present

### **"GPS shows 0.0, 0.0"**
→ ESP32 hasn't gotten GPS fix yet:
1. GPS module needs clear sky view (3-10 minutes outdoor)
2. Check GPS module connections (RX on pin 16, TX on pin 17)
3. Monitor serial output for "GPS data" messages

---

## 📱 App Structure Reference

```
lib/
├── main.dart                 # Entry point, auth routing
├── theme.dart               # Blue & white colors
├── services/
│   └── firebase_service.dart # RTDB streaming & auth
├── models/
│   ├── device_data.dart      # GPS, accelerometer data
│   └── contact_model.dart    # Emergency contacts
└── screens/
    ├── home_screen.dart      # Dashboard with device status
    ├── map_screen.dart       # Live GPS map
    ├── fall_detection_screen.dart # Accelerometer graph
    ├── alerts_screen.dart    # Emergency alert history
    └── contacts_screen.dart  # Emergency contact manager
```

---

## 🚀 Next Steps After Basic Setup

1. **Customize device ID**: Change `esp32_device_1` to match your ESP32 if needed
   - Update in: `lib/screens/home_screen.dart` (line 32)
   - Update in: ESP32 firmware `#define DEVICE_ID`
   - Update in: Firebase RTDB structure

2. **Add device pairing screen**: Let users pair multiple ESP32 devices
   - Add a `Settings` screen
   - Allow users to enter device ID and save to SharedPreferences

3. **Test fall detection**: 
   - Adjust `#define FALL_ACCEL_THRESHOLD` in ESP32 code
   - Default is 2.5g of acceleration

4. **Emergency contact notifications**:
   - Current app logs alerts to Firestore
   - Add SMS/push notifications (requires Firebase Cloud Messaging)

---

## 📝 Important Notes for Capstone

- **Keep Firebase rules OPEN for testing** (change to restrictive rules for production)
- **WiFi/API keys should NOT be committed to GitHub** (use env variables or .gitignore in production)
- **ESP32 WiFi password also should NOT be in public code** (use provisioning in production)
- Document all API keys and secrets in a `.env` file (add to `.gitignore`)

---

**Questions?** Check the comments in the code for more details!
