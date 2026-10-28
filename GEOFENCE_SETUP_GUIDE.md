# Geofence Feature - Complete Setup Guide

## Overview

The **Geofence Feature** lets users draw custom **polygon zones** and get notified when the device enters or exits them. Useful for:

- **Safety Monitoring**: Know when your elderly relative leaves home or a safe zone
- **Activity Tracking**: Track when someone arrives at work, school, or another location
- **Boundary Alerts**: Get notified if the wearer strays outside a defined area
- **Multiple Zones**: Create multiple polygons for different locations

**No API Keys Required** ✅ - This feature works with coordinates only (no map API needed; the map uses free OpenStreetMap tiles).

---

## System Architecture

```
┌─────────────────────────────────────────┐
│      Flutter Mobile App                 │
│  ┌───────────────────────────────────┐  │
│  │  Geofence Management Screen       │  │
│  │  - Draw polygon on map            │  │
│  │  - Add/Edit/Delete zones          │  │
│  │  - Enable/Disable toggle          │  │
│  └───────────────────────────────────┘  │
└──────────────┬──────────────────────────┘
               │
               ▼ (Firestore)
┌────────────────────────────────────────────┐
│  Firebase Cloud Database                   │
│  ┌──────────────────────────────────────┐  │
│  │ users/{userId}/geofences/{id}       │  │
│  │ - name, vertices:[{lat,lng}],       │  │
│  │   enabled, createdAt, updatedAt     │  │
│  │                                       │  │
│  │ users/{userId}/geofence_violations/ │  │
│  │ - geofenceId, type, location        │  │
│  └──────────────────────────────────────┘  │
│                                             │
│  RTDB: devices/{deviceId}/geofences/       │
│  (synced from Firestore for device access) │
└──────────────┬──────────────────────────────┘
               │
    ┌──────────┴──────────────┐
    ▼ (Real-time RTDB)        ▼ (Real-time RTDB)
┌─────────────────┐      ┌──────────────────────┐
│  ESP32 Device   │      │  Firebase Cloud      │
│                 │      │  Functions           │
│ - Fetch zones   │◄─────│  (push + SMS on     │
│ - GPS fix       │      │   violation)         │
│ - Point-in-poly │      └──────────────────────┘
│ - Confirm state │
│ - Log violations│
└─────────────────┘
```

---

## Features

### 1. **Geofence Management Screen**
Located in the bottom navigation bar under "Geofences"

#### Add a New Geofence (Polygon):
1. Tap **Add Polygon** in the bottom-right
2. Tap the map to place vertices — you need **at least 3 points** to form a valid polygon
3. Enter a **Polygon Name** (e.g., "Home", "Work", "School")
4. Tap **Save Polygon**
5. The polygon is saved to Firestore and instantly synced to the ESP32 device

**How to Find Coordinates / Draw a Zone:**
- The map is OpenStreetMap — pan/zoom to the area and tap to trace the boundary
- Use Google Maps to look up a place, then trace the equivalent shape in the app
- Ask the device to report its current location, then draw a polygon around it

#### Edit a Geofence:
1. Tap a geofence in the list
2. Tap "Edit"
3. Move/add/remove vertices or rename the polygon
4. Tap "Update Polygon"

#### Delete a Geofence:
1. Tap a geofence in the list
2. Tap "Delete"
3. Confirm deletion

#### Enable/Disable Zones:
- Toggle the switch on each geofence card
- Disabled zones are not synced to the device and won't trigger violations
- Useful for temporarily pausing monitoring without deleting

### 2. **Geofence List View**
- List showing all created polygons
- Shows the vertex count and a preview of the first vertex
- Live inside/outside status per zone (green = inside, red = outside, blue = unknown)
- Tap to edit, delete, or toggle

### 3. **Violation Logging**
When the device exits or enters a geofence:
- ✅ Logged to `/devices/{deviceId}/geofence_violations/{pushId}` in RTDB
- ✅ Bridged to Firestore `users/{userId}/geofence_violations/` and Alert History
- ✅ Viewable in the **Alerts** screen
- Data format (written by the ESP32):
  ```json
  {
    "geofenceId": "zone_123",
    "name": "Home",
    "type": "exited",   // or "entered"
    "lat": 37.7749,
    "lng": -122.4194,
    "distance": 520.5,  // meters from the polygon centroid
    "eventUtc": 1681234567,
    "timestamp": 1681234567890   // server timestamp (.sv)
  }
  ```

---

## Setup Instructions

### Part 1: App Configuration

**No API keys needed!** The geofence screen is already wired into the bottom navigation bar (the "Geofences" tab). No code changes are required — the screen, model, and sync logic all live in the app already.

### Part 2: ESP32 Firmware

1. **Verify Libraries**
   - The firmware needs the ArduinoJson library (already listed in `ESP32_CONFIG_TEMPLATE.h`):
     ```
     ArduinoJson by Benoit Blanchon (6.x recommended)
     ```

2. **Verify Firebase Path Configuration**
   - Geofences are read from: `/devices/{deviceId}/geofences` (an array written by the app)
   - Violations are logged to: `/devices/{deviceId}/geofence_violations/{pushId}`

3. **GPS Configuration**
   - Geofencing requires a valid GPS fix
   - The device duty-cycles GPS and only wakes it to check geofences when configured:
     - `GPS_ACTIVE_INTERVAL_MS` = 60000 (1 min) when geofences exist
     - `GPS_ACTIVE_NOFENCE_MS` = 300000 (5 min) when none
   - May take 5-10 minutes outdoors for the first GPS lock

### Part 3: Firebase Configuration

**Firestore Rules** (if using only Firebase Auth):
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection
    match /users/{userId} {
      allow read, write: if request.auth.uid == userId;

      // Geofences subcollection
      match /geofences/{document=**} {
        allow read, write: if request.auth.uid == userId;
      }

      // Geofence violations
      match /geofence_violations/{document=**} {
        allow read, write: if request.auth.uid == userId;
      }
    }
  }
}
```

**Realtime Database Rules**:
```json
{
  "rules": {
    "devices": {
      "$deviceId": {
        "geofences": {".read": true, ".write": true},
        "geofence_violations": {".read": true, ".write": true},
        "commands": {".read": true, ".write": true}
      }
    }
  }
}
```

---

## How It Works

### On the App
1. User draws a polygon: `GeofenceScreen` → `firebase.addGeofence()`
2. Geofence saved to Firestore: `users/{userId}/geofences/{id}` (with `vertices`)
3. Synced to device RTDB: `devices/{deviceId}/geofences` (an array of `{id, name, vertices}`)
4. User can view/edit polygons on the interactive map
5. Violations appear in Alert History and as in-app SnackBar notifications

### On the ESP32 Device
1. **Download**: `fetchGeofences()` runs on startup, every `GEOFENCE_REFRESH_MS` (10 min), and when `commands/refreshGeofences` is set
2. **Evaluate on each GPS fix**: `geofenceEvaluate()` runs point-in-polygon for every valid fix — there is no fixed 30-second polling loop; it's event-driven off the GPS duty cycle
3. **Confirm state change**: a zone only flips state after `GEOFENCE_CONFIRM_FIXES` (2) consecutive fixes that disagree with the current state, spaced `GEOFENCE_CONFIRM_GAP_MS` (5 s) apart — this suppresses GPS jitter at boundaries
4. **Log violation**: on a confirmed enter/exit, the device POSTs to `/devices/{deviceId}/geofence_violations/`
5. **Serial debugging**: prints geofence activity to the serial monitor (see below)

---

## Serial Monitor Output Examples

### Successful Setup
```
=== Guardian Firmware v2.0.0 ===
[GEOFENCE] 2 geofence(s) loaded

[GEOFENCE] 'Home' exited
[GEOFENCE] 'Work' entered
```

### No Geofences
```
[GEOFENCE] 0 geofence(s) loaded
```

### Refresh / Command
```
[CMD] locateNow=0 refreshGeofences=1
[GEOFENCE] 1 geofence(s) loaded
```

---

## Testing the Feature

### Test 1: Create a Geofence
1. Open app → Geofences tab → Tap **Add Polygon**
2. Tap the map to place 3+ vertices around your location
3. Enter a name: "Test Home"
4. Tap **Save Polygon**
5. Check serial monitor: should log `[GEOFENCE] 1 geofence(s) loaded`

### Test 2: Verify the Polygon
1. Check the geofence card shows the correct vertex count
2. Verify the polygon renders on the map with the correct shape
3. Tap the zone to edit and confirm the vertices match where you tapped

### Test 3: GPS Tracking
1. Ensure the device is outdoors with sky view
2. Check serial monitor outputs GPS fixes
3. Move the device around and watch the location update

### Test 4: Violation Detection
1. Draw a polygon around a known location
2. Move the device clearly outside the polygon (with a GPS fix)
3. Check:
   - Serial monitor shows `[GEOFENCE] '<name>' exited`
   - App's Alert History shows the violation
   - ESP32 RTDB shows the log under `/devices/{deviceId}/geofence_violations/`
4. Move back inside the polygon
5. Serial monitor should show `[GEOFENCE] '<name>' entered`

### Test 5: Multiple Geofences
1. Create 3-4 polygons in different areas
2. Move between them (with valid GPS)
3. Verify each triggers the correct violation type (entered/exited)
4. Check that disabled zones are not synced and don't trigger violations

---

## Troubleshooting

### "Invalid Polygon" / Can't Save
**Problem**: The Save button is disabled.

**Solution**:
- A polygon needs **at least 3 vertices** — tap the map at least 3 times
- Enter a name in the "Polygon Name" field
- Use the map, not a lat/lng form; there is no manual coordinate entry in v2

### "No GPS Fix" Issue
**Problem**: Geofences never trigger; no `[GEOFENCE] ... entered/exited` lines.

**Solution**:
- Move device outdoors (GPS needs line-of-sight to satellites)
- Wait 5-10 minutes for the first fix
- Check GPS module wiring on the ESP32 (GT-U8 TX → GPIO 5, RX → GPIO 6)
- Verify GT-U8 module is powered (3.3V)
- Try moving away from buildings/trees

### Geofences Not Syncing
**Problem**: Geofence created in app but not appearing on device.

**Solution**:
- Check serial monitor for `[GEOFENCE] N geofence(s) loaded`
- Verify the device has internet connectivity
- The device ID is auto-generated (`guardian_<mac>`); the app learns it over BLE — confirm the app is bound to the correct device
- Verify the geofence exists in Firestore: Firebase Console → Collections → Users → Your ID → geofences
- Confirm the geofence is **enabled** (disabled zones are not synced)
- Check that the polygon has ≥3 vertices

### False Violations
**Problem**: Getting too many "entered"/"exited" messages at a boundary.

**Solution**:
- GPS accuracy is typically ±20-50 m, causing jitter near the polygon edge
- The firmware already requires 2 consecutive confirming fixes (`GEOFENCE_CONFIRM_FIXES`) — increase it to 3 in section 1 of `guardian_firmware.ino` for stricter filtering
- Draw larger polygons to reduce boundary crossings
- Avoid placing the polygon edge right on top of a frequently-occupied location

### Distance Calculation Seems Wrong
**Problem**: Reported `distance` looks off.

**Solution**:
- `distance` is measured to the polygon **centroid** (average of the vertices), so a large polygon will report a larger distance even when the device is inside it — this is expected
- GPS accuracy varies by environment (±20-50 m is normal)
- Move to an open area for better accuracy

### Firebase Write Errors
**Problem**: "Failed to log violation: Permission denied".

**Solution**:
- Update Firebase Realtime Database rules (see configuration above)
- Ensure `FIREBASE_AUTH` in `secrets.h` is valid (and rotate it if it was ever committed)
- Check the device path is under `/devices/{deviceId}`

---

## Advanced Configuration

All tunables live in **section 1** of `guardian_firmware.ino`:

### Geofence Confirmation
```cpp
constexpr uint8_t  GEOFENCE_CONFIRM_FIXES = 2;      // consecutive fixes needed to log enter/exit
constexpr uint32_t GEOFENCE_CONFIRM_GAP_MS = 5000;  // wait between confirming fixes
```
Raise `GEOFENCE_CONFIRM_FIXES` to reduce false violations (at the cost of slower detection).

### Refresh Interval
```cpp
constexpr uint32_t GEOFENCE_REFRESH_MS = 600000;  // re-download geofences every 10 min
```

### Max Geofences / Vertices
```cpp
constexpr int MAX_GEOFENCES = 10;
constexpr int MAX_VERTICES  = 20;
```
Raise `MAX_GEOFENCES` to support more zones, or `MAX_VERTICES` for more detailed polygons.

### GPS Duty Cycle (when geofences are active)
```cpp
constexpr uint32_t GPS_ACTIVE_INTERVAL_MS = 60000;    // 1 min between checks when geofences exist
constexpr uint32_t GPS_ACTIVE_NOFENCE_MS = 300000;    // 5 min when no geofences
```
There is no `GEOFENCE_CHECK_INTERVAL_MS` in v2 — the cadence is driven by the GPS duty cycle, and evaluation runs on every valid fix.

---

## Database Schema

### Firestore
```
users/{userId}
  └─ geofences/{geofenceId}
     ├─ userId: string
     ├─ name: string
     ├─ vertices: array<{lat: number, lng: number}>   (≥ 3 vertices)
     ├─ enabled: boolean
     ├─ createdAt: timestamp
     └─ updatedAt: timestamp

users/{userId}
  └─ geofence_violations/{violationId}
     ├─ geofenceId: string
     ├─ name: string
     ├─ type: "entered" | "exited"
     ├─ lat: number
     ├─ lng: number
     ├─ distance: number (meters to centroid)
     ├─ eventUtc: number
     └─ timestamp: timestamp
```

### Realtime Database
```
devices/{deviceId}
  └─ geofences/            (array written by the app)
     └─ [ { id, name, vertices: [ {lat, lng}, ... ] }, ... ]

devices/{deviceId}
  └─ geofence_violations/
     └─ {pushId}
        ├─ geofenceId: string
        ├─ name: string
        ├─ type: "entered" | "exited"
        ├─ lat: number
        ├─ lng: number
        ├─ distance: number
        ├─ eventUtc: number
        └─ timestamp: number (server timestamp)
```

---

## Future Enhancements

- [ ] **Location Picker**: Tap to select from recent locations
- [ ] **Address Search**: Search by address name instead of drawing manually
- [ ] **Circle Zones**: Optional circle (center + radius) mode in addition to polygons
- [ ] **Push Notifications**: Send device notifications on geofence violations (already wired via Cloud Functions)
- [ ] **Exit Alert Timeout**: Alert guardians after device is outside for X minutes
- [ ] **Scheduled Zones**: Zones that are only active during certain times
- [ ] **Geofence Groups**: Combine multiple zones (e.g., "Safe Zones")
- [ ] **Smart Notifications**: Reduce redundant notifications with smart filtering

---

## Support & Debugging

For detailed logs, check:
1. **Serial Monitor** (Arduino IDE): Real-time firmware logs (`[GEOFENCE]`, `[CMD]`, `[STATUS]`)
2. **Firebase Console**: Geofence data and violations
3. **App Alerts Screen**: Historical violations logged to app
4. **Flutter DevTools**: Network requests to Firestore

---

**Version**: 2.0.0
**Last Updated**: October 12, 2026
**Status**: Polygon-based, event-driven geofencing
