# Guardian ESP32 Wearable App - Complete Setup Guide

> The mobile app is branded **GuardianNako** and the wearable is **GuardianNemo**.
> Backend: Firebase (Auth + Realtime Database + Firestore + Cloud Functions).
> Firmware: ESP32-S3 SuperMini, v2.0.0, event-driven.

## 🔧 What's Configured

✅ **Maps** — free OpenStreetMap (no API key), live Guardian tracking, road-following route (OSRM), and the geofence manager (draw / edit / delete polygons).  
✅ **Push notifications** — FCM + Cloud Functions (SOS, fall, geofence breach) with email-to-SMS fallback.  
✅ **Auth** — Email/password **and** Google Sign-In, with inline validation, "Remember me" and "Forgot password".  
✅ **Account settings** — edit display name, change email (verified link), change password (re-authenticated).  
✅ **Multiple devices** — pair, switch, rename and remove several Guardians from one account.  
✅ **Alert sound** — bundled tones or a custom audio file for emergency alerts.  
✅ **Device settings** — wearer photo + name, and BLE WiFi provisioning.  
✅ **Required permissions** — Location, Internet, Network, Bluetooth, Camera, Notifications.

---

## 📋 Complete Setup Checklist

### STEP 1: Maps Configuration (No Setup Required!)

The app uses **OpenStreetMap** with `flutter_map` — free, no API key. The map also draws:
- The **wearer** (device) marker with their photo (set in Device Settings).
- The **Guardian's** live location (blue "You" marker).
- A **road-following route** from Guardian → wearer (OSRM, `driving`/`foot` toggle).
- **Geofence polygons** — drawn, edited and deleted on the map (no separate tab).

✅ No sign-ups, payments, or API keys needed.

### STEP 2: Configure ESP32 Firmware

The ESP32 needs WiFi and Firebase credentials to send data to the app.

#### A. Configure WiFi & Firebase (`secrets.h`)

Private settings live in `secrets.h` (next to the `.ino`); tunables live in section 1 of `guardian_firmware.ino`.

1. Copy the template, then fill in your values:

   ```bash
   cp ESP32_CONFIG_TEMPLATE.h secrets.h
   ```

2. Edit `secrets.h`:

   ```cpp
   #define FIREBASE_HOST  "https://YOUR_PROJECT-default-rtdb.firebaseio.com"

   // Choose ONE auth option:
   //   OPTION A — legacy database secret (simplest, bypasses security rules)
   #define FIREBASE_AUTH  "PASTE_NEW_DATABASE_SECRET_HERE"
   //   OPTION B — per-device email/password sign-in (recommended)
   // #define FIREBASE_API_KEY        "YOUR_WEB_API_KEY"
   // #define FIREBASE_AUTH_EMAIL     "guardian@yourdomain.com"
   // #define FIREBASE_AUTH_PASSWORD  "device-password"

   #define PROVISIONING_PIN  ""   // optional BLE PIN (empty = none)
   ```

3. WiFi credentials are provisioned over BLE from the app (or auto-migrated from v1 NVS keys). There is **no** hardcoded `WIFI_SSID`, `WIFI_PASSWORD`, or `DEVICE_ID` — the device ID is auto-generated as `guardian_<mac>` at boot and stored in NVS.

4. **v2 extras you get for free:**
   - Up to **3 saved WiFi networks** (strongest is chosen).
   - **Hold the button 5 s while powering up** to erase saved WiFi and reopen BLE setup.
   - Event-driven GPS (duty-cycled) + 100 Hz IMU fall detection with a 15 s "I'm OK" cancel window.
   - The device only uploads on events + heartbeat, and retries alerts until delivered.

5. Never commit `secrets.h` — it is already in `.gitignore`.

#### B. Get Firebase Realtime Database Secret Token

1. Firebase Console → Project → **Realtime Database** → ⚙️ **Database secrets**.
2. Copy the token and paste it into `FIREBASE_AUTH`.

#### C. Upload to ESP32

1. Use Arduino IDE or PlatformIO.
2. Install libraries:
   - `TinyGPS++` by Mikal Hart
   - `MPU6050` by Electronic Cats
   - `ArduinoJson` by Benoit Blanchon (6.x recommended)

   (WiFi, HTTPClient, Preferences, and BLE ship with the ESP32 core — the old "Firebase ESP32 Client" is not used.)

3. Board: `ESP32S3 Dev Module` (esp32 core 3.x).
4. `USB CDC On Boot` → **Enabled**.
5. Baud: `115200`. Upload the sketch.

   Pins (ESP32-S3 SuperMini): MPU6050 I2C `SDA=8 / SCL=9`, GPS `Serial2 RX=5 / TX=6`, SOS button `GPIO 4` (active LOW), status LED `GPIO 2`.

### STEP 3: Set Up Firebase Realtime Database (RTDB) Rules

The app reads sensor data **and** writes its FCM push token + device ownership + on-demand location commands, so the rules must allow those nodes.

1. Firebase Console → **Realtime Database** → **Rules**.
2. Replace with:

```json
{
  "rules": {
    "devices": {
      "$deviceId": {
        ".read": true,
        "sensors": { ".write": true },
        "emergency": { ".write": true },
        "geofences": { ".write": "auth != null" },
        "geofence_violations": { ".write": true },
        "commands": { ".write": "auth != null" },
        "owner": { ".write": "auth != null" },
        "fcmTokens": {
          "$userId": { ".write": "auth != null && auth.uid === $userId" }
        }
      }
    }
  }
}
```

3. Click **Publish**.

> `sensors` / `emergency` / `geofence_violations` stay open so the ESP32 can write (it authenticates as a service account or via database secret). `commands`, `owner` and `fcmTokens` are written by the signed-in phone, so they require `auth != null`. `smsCooldowns` is written by the Cloud Function (admin SDK, bypasses rules). Keep rules open for capstone testing; tighten before production.

### STEP 4: Create Initial Test Data (Optional)

1. Firebase Console → **Realtime Database** → `+` → add `devices` → `guardian_<mac>` → `sensors`:

```json
{
  "gps": { "lat": 10.3157, "lng": 123.8854 },
  "accelerometer": { "x": 0.5, "y": 1.2, "z": 9.8 },
  "fallDetected": false,
  "timestamp": {".sv": "timestamp"},
  "hbIntervalS": 120,
  "mode": "active",
  "imuOk": true,
  "rssi": -55,
  "firmware": "2.0.0"
}
```

2. Add an `emergency` node:

```json
{ "active": false }
```

### STEP 5: Test the App

```bash
cd d:\PWPD\pwpd
flutter pub get
flutter run
```

**Navigation — 5 bottom tabs** (Dashboard is the center button):

- ✅ **Dashboard** → device data, emergency banner, device switcher (top-right), 3-dots menu
- ✅ **Map** → wearer marker + Guardian "You" marker + route + geofence draw/edit/delete
- ✅ **Movement** → fall / movement status
- ✅ **Alerts** → alert history (SOS, fall, geofence enter/exit)
- ✅ **Contacts** → add/edit/delete emergency contacts, tap to call

**Settings (Dashboard 3-dots → Settings):**

- ✅ **Account** → display name, email, password
- ✅ **Device Settings** → wearer photo + name + device setup
- ✅ **Devices** → add / switch / rename / remove paired devices
- ✅ **Language** → English / Filipino toggle
- ✅ **Alert sound** → bundled tones + custom file

**Auth screen:**

- ✅ Sign In / Register (inline field validation, "Remember me", "Forgot password")
- ✅ **Continue with Google**

### STEP 6: Enable Push Notifications (Works When App Is Closed)

FCM **receiving** is free. **Sending** uses Cloud Functions, which needs the **Blaze plan** (card on file, but the free tier easily covers a capstone: 2M invocations/month).

#### 6.1 Upgrade Firebase to Blaze

1. Firebase Console → ⚙️ Project settings → **Upgrade** (bottom-left "Spark" badge).
2. Add a card. You stay at $0 under the free tier.

#### 6.2 Deploy the Cloud Functions

The `functions/` folder already contains the triggers (`onEmergency`, `onGeofenceViolation`). Deploy them:

```powershell
npm install -g firebase-tools
firebase login
firebase use pwpd-5e580
firebase deploy --only functions
```

#### 6.3 (Optional) SMS fallback secrets

Push works without this. For email-to-SMS alerts to emergency contacts (gateways include Globe / Smart / Sun / DITO and US carriers):

```powershell
firebase functions:secrets:set EMAIL_USER
firebase functions:secrets:set EMAIL_PASS
```

#### 6.4 Android notification permission

On Android 13+, the OS asks "Allow notifications?" on first launch. If denied, re-enable under Settings → Apps → your app → Notifications. Android-only is **fully free**.

#### 6.5 iOS (optional, not free)

iOS push requires the **Apple Developer Program ($99/yr)**. Upload the APNs `.p8` key under Firebase Console → Project settings → Cloud Messaging. Skip for an Android-only demo.

#### 6.6 Test with the app closed

1. Pair a device in the app (registers the phone's FCM token at `devices/{id}/fcmTokens/{uid}` for **every** paired device).
2. Force-close the app (swipe it away from recents).
3. Trigger an alert — write to RTDB:

```
/devices/{deviceId}/emergency = { "active": true, "reason": "SOS button pressed", "lat": ..., "lng": ... }
```

4. A system notification with sound should appear within ~1–3 s even though the app is dead.

**Why it works when closed:** the Cloud Function sends a *notification* message (has a `notification` block), so the OS displays it without the app running. A `FirebaseMessaging.onBackgroundMessage` handler is **not** needed for notification messages — only for data-only messages.

### STEP 7: Enable Google Sign-In (Optional)

1. Firebase Console → **Authentication** → **Sign-in method** → enable **Google**.
2. Add your Android app's **SHA-1** fingerprint: Firebase Console → Project settings → your Android app → **Add fingerprint**.
   - Get it with: `cd android && ./gradlew signingReport` (look for `SHA1` under the debug/upload config).
3. Rebuild. If Google sign-in fails with a config error, the SHA-1 is usually missing.

---

## 🔌 How ESP32 Connects to the App

```
┌─────────────────────────────────────────────┐
│         ESP32 Device                        │
│  (WiFi + MPU6050 + GT-U8 GPS)              │
└────────────────┬────────────────────────────┘
                 │ (Sends sensor data)
                 │ WiFi/Internet
                 ▼
    ┌────────────────────────────┐
    │  Firebase Realtime DB      │
    │  /devices/guardian_<mac>   │
    │  ├── sensors (GPS, accel)  │
    │  ├── emergency (alert)     │
    │  ├── geofence_violations   │
    │  └── commands/locateNow    │
    └──────┬──────────────┬──────┘
           │              │ (Cloud Function watches)
           │              ▼
           │   ┌──────────────────────┐
           │   │  Cloud Functions     │
           │   │  → FCM push + SMS    │
           │   └──────────┬───────────┘
           │              │
           │ (Stream)     │ (FCM push)
           ▼              ▼
    ┌──────────────────────────┐
    │  Flutter App (phone)     │
    │  + system notification   │
    └──────────────────────────┘
```

**Key points:**
- **Device ID is auto-generated** (`guardian_<mac>`) and provisioned over BLE — the app learns it automatically.
- **Firebase is the hub** — all communication goes through RTDB.
- **No direct device↔phone connection** except one-time BLE provisioning.
- **Notifications** are triggered server-side by Cloud Functions, so they arrive even when the app is closed.
- **One account can own many devices** — each paired device gets its own FCM token registration.

---

## 🆘 Troubleshooting

### "Map screen is blank or not loading"
→ Check internet. OpenStreetMap tiles require network. No API key needed.

### "Route line doesn't appear"
→ Tap **View on Map** during an alert. Requires Guardian location permission and internet (OSRM routing server). Falls back to recentering if OSRM is unreachable.

### "Device is offline / no data showing"
1. WiFi credentials provisioned (watch the `[STATUS]` serial line).
2. `FIREBASE_HOST` / `FIREBASE_AUTH` correct.
3. ESP32 has internet.
4. RTDB rules allow reads/writes.
5. `timestamp` is fresh — offline only after `2.5 × hbIntervalS` (≈5 min active / 12.5 min resting).

### "Notifications don't arrive when app is closed"
1. Cloud Functions **deployed** (`firebase deploy --only functions`).
2. Project on **Blaze** plan (Spark doesn't run functions).
3. A device is **paired** in the app (token registered at `devices/{id}/fcmTokens`).
4. Android 13+: notification permission granted.
5. iOS: APNs `.p8` key uploaded.
6. Check function logs: `firebase functions:log`.

### "Can't log in to app"
1. Firebase Authentication → Email/Password enabled.
2. User exists in Firebase Console → Authentication.
3. Phone has internet.
4. `google-services.json` / `GoogleService-Info.plist` present.

### "Google sign-in fails"
1. Google provider enabled in Firebase Authentication.
2. App **SHA-1** fingerprint added (Project settings → Android app).
3. See Step 7.

### "GPS shows 0.0, 0.0"
1. GPS needs clear sky (5–10 min outdoor for first lock).
2. Check GT-U8 wiring: TX → `PIN_GPS_RX` (GPIO 5), RX → `PIN_GPS_TX` (GPIO 6).
3. Watch serial output for GPS fix lines.

---

## 📱 App Structure Reference

```
lib/
├── main.dart                       # Entry point, FCM setup, auth routing
├── theme.dart                      # Blue & white theme (#1565C0)
├── services/
│   ├── firebase_service.dart       # Auth (email/Google), RTDB streams, Firestore CRUD, FCM token, multi-device
│   ├── device_config_service.dart  # Active-device selection + legacy migration
│   ├── ble_service.dart            # BLE WiFi provisioning
│   ├── language_service.dart       # English / Filipino toggle
│   ├── routing_service.dart        # OSRM road-following route
│   └── alert_sound_service.dart    # Alert tone (bundled/custom) selection
├── models/
│   ├── device_data.dart            # GPS + accelerometer + heartbeat
│   ├── contact_model.dart          # Emergency contacts (+ carrier gateways)
│   ├── geofence_model.dart         # Geofence zones
│   ├── device_settings_model.dart  # Wearer photo + name
│   ├── paired_device.dart          # Paired device list item
│   └── alert_sound.dart            # Alert sound models
├── widgets/
│   └── toast_notification.dart     # Toast + offline banner mixin
└── screens/
    ├── auth_screen.dart            # Login / Register / Google Sign-In
    ├── home_screen.dart            # 5-tab shell + settings menu + emergency dialog
    ├── map_screen.dart             # Live GPS map + geofence manager + route
    ├── fall_detection_screen.dart  # Movement / fall status
    ├── alerts_screen.dart          # Alert history
    ├── contacts_screen.dart        # Emergency contacts
    ├── devices_screen.dart         # Multi-device management
    ├── device_setup_screen.dart    # BLE WiFi setup
    ├── device_settings_screen.dart # Wearer photo, name, WiFi
    ├── account_settings_screen.dart# Account name/email/password
    └── alert_sound_screen.dart     # Alert sound picker
```

Cloud Functions live in `functions/index.js` (`onEmergency`, `onGeofenceViolation`).

---

## 🚀 Already Implemented (no setup needed)

- **Device pairing** — automatic via BLE provisioning; no manual device ID.
- **Multiple devices** — add / switch / rename / remove from Settings → Devices (or the dashboard switcher).
- **Google Sign-In** — one-tap auth alongside email/password.
- **Account settings** — name, email (verified change) and password (re-auth required).
- **Alert sound** — bundled tones + custom audio, played on emergency.
- **Geofence manager** — draw / edit / delete polygons on the Map screen.
- **Guardian live location + routing** — `geolocator` stream + OSRM route.
- **Wearer photo** — stored as base64 in Firestore, shown on map + dashboard.

---

## 📝 Important Notes for Capstone

- **Keep Firebase rules OPEN for testing** (tighten for production).
- **Never commit secrets** — `secrets.h`, `.env`, `google-services.json` keys stay gitignored.
- **Cloud Functions need Blaze** (free tier is enough for a demo).
- **Google Sign-In needs the app SHA-1** registered in the Firebase console.
- Document all API keys in a `.env` file (add to `.gitignore`).

---

**Questions?** Check the comments in the code for more details!
