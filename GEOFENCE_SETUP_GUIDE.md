# Geofence Feature - Complete Setup Guide

## Overview

The **Geofence Feature** enables users to define custom geographic zones and receive notifications when a device enters or exits these zones. This is useful for:

- **Safety Monitoring**: Know when your elderly relative leaves home or a safe zone
- **Activity Tracking**: Track when someone arrives at work, school, or other important locations
- **Boundary Alerts**: Get notified if the wearer goes too far from home
- **Multiple Zones**: Create multiple geofences for different locations

**No API Keys Required** ✅ - This feature works with coordinates only (no maps needed)

---

## System Architecture

```
┌─────────────────────────────────────┐
│      Flutter Mobile App              │
│  ┌───────────────────────────────┐  │
│  │  Geofence Management Screen   │  │
│  │  - Add/Edit/Delete Zones      │  │
│  │  - Visual Map with Circles    │  │
│  │  - Enable/Disable Toggle      │  │
│  └───────────────────────────────┘  │
└──────────────┬──────────────────────┘
               │
               ▼ (Firestore)
┌────────────────────────────────────────────┐
│  Firebase Cloud Database                   │
│  ┌──────────────────────────────────────┐  │
│  │ users/{userId}/geofences/{id}       │  │
│  │ - name, latitude, longitude         │  │
│  │ - radiusMeters, enabled             │  │
│  │                                       │  │
│  │ users/{userId}/geofence_violations/ │  │
│  │ - geofenceId, type, location        │  │
│  └──────────────────────────────────────┘  │
│                                             │
│  RTDB: devices/{deviceId}/geofences/      │
│  (synced from Firestore for device access) │
└──────────────┬──────────────────────────────┘
               │
    ┌──────────┴──────────────┐
    ▼ (Real-time RTDB)        ▼ (Real-time RTDB)
┌─────────────────┐      ┌──────────────────────┐
│  ESP32 Device   │      │  Firebase Cloud      │
│                 │      │  Functions           │
│ - Fetch zones   │◄─────│  (optional: send     │
│ - GPS location  │      │   push notifications)│
│ - Calculate     │      └──────────────────────┘
│   distance      │
│ - Check bounds  │
│ - Log violations│
└─────────────────┘
```

---

## Features

### 1. **Geofence Management Screen**
Located in the bottom navigation bar under "Geofences"

#### Add a New Geofence:
1. Tap the **+** button in the top-right
2. Enter the **Zone Name** (e.g., "Home", "Work", "School")
3. Enter **Latitude** (decimal format, e.g., 40.7128)
4. Enter **Longitude** (decimal format, e.g., -74.0060)
5. Adjust the **Radius slider** (100m - 5km)
6. Tap "Create"
7. The geofence is instantly synced to the ESP32 device

**How to Find Coordinates:**
- Use Google Maps: Right-click on location → Copy coordinates
- Use GPS apps: Check your device's location
- Ask the device to report current location
- Search online: "[Place Name] coordinates"

Example:
- New York: 40.7128°N, 74.0060°W
- San Francisco: 37.7749°N, 122.4194°W
- London: 51.5074°N, 0.1278°W

#### Edit a Geofence:
1. Tap on a geofence in the list
2. Tap "Edit" button
3. Modify name, coordinates, or radius
4. Tap "Save"

#### Delete a Geofence:
1. Tap on a geofence in the list
2. Tap "Delete" button
3. Confirm deletion

#### Enable/Disable Zones:
- Toggle the switch on each geofence card
- Disabled zones won't trigger violations
- Useful for temporarily pausing monitoring without deleting

### 2. **Geofence List View**
- Simple list showing all created geofences
- See coordinates in decimal format (6 decimal places ≈ 0.1 meter accuracy)
- Status indicator showing enabled/disabled
- Tap to expand for more options

### 3. **Violation Logging**
When the device exits or enters a geofence:
- ✅ Logged to user's **Geofence Violations** collection
- ✅ Sent to app's Alert History
- ✅ Viewable in **Alerts** screen
- Data format:
  ```json
  {
    "geofenceId": "zone_123",
    "name": "Home",
    "type": "exited",  // or "entered"
    "latitude": 37.7749,
    "longitude": -122.4194,
    "distance": 520.5,  // meters from geofence center
    "timestamp": 1681234567890
  }
  ```

---

## Setup Instructions

### Part 1: App Configuration

**No API keys needed!** The geofence screen uses a simple form-based interface with no external dependencies.

Just add the Geofence Screen to your bottom navigation bar:

1. Open `lib/main.dart`
2. Add to navigation items:
   ```dart
   BottomNavigationBarItem(
     icon: Icon(Icons.location_on_outlined),
     activeIcon: Icon(Icons.location_on),
     label: 'Geofences',
   ),
   ```

3. Add to the body widget selector:
   ```dart
   case 3:  // Add after other tabs
     return GeofenceScreen(userId: userId, deviceId: deviceId);
   ```

That's it! No dependencies to install, no API keys to configure.

### Part 2: ESP32 Firmware

1. **Verify Includes**
   - Ensure your firmware includes Arduino JSON library:
   ```bash
   // In Arduino IDE:
   // Sketch → Include Library → Manage Libraries
   // Search for "ArduinoJson" and install
   ```

2. **Verify Firebase Path Configuration**
   - Geofences are read from: `/devices/{DEVICE_ID}/geofences`
   - Violations logged to: `/devices/{DEVICE_ID}/geofence_violations/{timestamp}`

3. **GPS Configuration**
   - Geofencing requires valid GPS signal
   - ESP32 will print "[GEOFENCE] Waiting for GPS fix..." until GPS is available
   - May take 30-60 seconds to get first GPS fix outdoors

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
        "geofence_violations": {".read": true, ".write": true}
      }
    }
  }
}
```

---

## How It Works

### On the App
1. User creates geofence: `GeofenceScreen` → `firebase.addGeofence()`
2. Geofence saved to Firestore: `users/{userId}/geofences/{id}`
3. Synced to device RTDB: `devices/{deviceId}/geofences`
4. User can view/edit geofences on interactive map
5. Violations appear in Alert History

### On the ESP32 Device
1. **Initialization**: Firmware calls `fetchGeofences()` on startup
2. **Periodic Check**: Every 30 seconds, `checkGeofences()` is called
3. **Distance Calculation**: Uses Haversine formula to calculate distance from GPS to each geofence center
4. **State Change Detection**: Compares current position to previous state to detect "entered" or "exited"
5. **Violation Logging**: On state change, RTDB logs to `/devices/{deviceId}/geofence_violations/`
6. **Serial Debugging**: Prints geofence checks to serial monitor:
   ```
   [GEOFENCE CHECK] Location: 37.7749, -122.4194
   [GEOFENCE] Zone 'Work': entered (distance: 120.5 m)
   [GEOFENCE CHECK] Complete
   ```

---

## Serial Monitor Output Examples

### Successful Setup
```
=== ESP32 Guardian Firmware Started ===
Ready for operation.
[GEOFENCE] Fetched 2 geofences from Firebase

[GEOFENCE CHECK] Location: 37.7749, -122.4194
[GEOFENCE] Zone 'Home': entered (distance: 200.5 m)
[GEOFENCE] Zone 'Work': exited (distance: 8500.0 m)
[GEOFENCE CHECK] Complete

Geofence violation logged to Firebase
```

### Waiting for GPS
```
[GEOFENCE] Waiting for GPS fix...
[STATUS] Button State: Released | Emergency Active: NO | WiFi: Connected
```

### No Geofences
```
[GEOFENCE] Fetched 0 geofences from Firebase
```

---

## Testing the Feature

### Test 1: Create a Geofence
1. Open app → Geofences tab → Tap +
2. Enter zone name: "Test Home"
3. Enter latitude: 40.7128
4. Enter longitude: -74.0060
5. Set radius: 500m
6. Tap "Create"
7. Check serial monitor: Should log "Fetched 1 geofences"

### Test 2: Verify Coordinates
1. Check the geofence card displays the coordinates correctly
2. Verify coordinates are shown to 6 decimal places
3. Visit https://maps.google.com and paste coordinates to verify location

### Test 3: GPS Tracking
1. Enable GPS on your device
2. Check serial monitor outputs GPS coordinates
3. Move device around and watch serial output update
4. Verify GPS coordinates match actual location

### Test 4: Violation Detection
1. Create a geofence around a known location with coordinates
2. Move the device ~100m away from the geofence center
3. Check:
   - Serial monitor shows "exited" message
   - App's Alert History shows the violation
   - ESP32 RTDB shows log under `/devices/{deviceId}/geofence_violations/`
4. Move back within the zone
5. Serial monitor should show "entered" message

### Test 5: Multiple Geofences
1. Create 3-4 geofences in different cities (use real world coordinates)
2. Simulate movement between zones by simulating GPS changes
3. Verify each triggers correct violation type (entered/exited)
4. Check that disabled zones don't trigger violations

---

## Troubleshooting

### "Invalid Coordinates" Error
**Problem**: App shows "Invalid coordinates. Lat: -90 to 90, Lng: -180 to 180"

**Solution**:
- Latitude must be between -90 and 90
- Longitude must be between -180 and 180
- Use decimal format (e.g., 40.7128, not "40°42'52.5"N")
- Check you didn't swap latitude and longitude

### "No GPS Fix" Issue
**Problem**: [GEOFENCE] Waiting for GPS fix...

**Solution**:
- Move device outdoors (GPS needs line-of-sight to satellites)
- Wait 2-3 minutes for first fix
- Check GPS module wiring on ESP32
- Verify NEO-6M module is powered (5V)
- Try moving away from buildings/trees

### Geofences Not Syncing
**Problem**: Geofence created in app but not appearing on device

**Solution**:
- Check Firebase connection: Look for "Firebase connected" in serial monitor
- Verify device has internet connectivity
- Check DEVICE_ID matches in app and firmware
- Verify Firestore geofence exists: 
  - Go to Firebase Console → Collections → Users → Your ID → geofences
  - Check geofence document has correct structure

### False Violations
**Problem**: Getting too many "entered" and "exited" messages

**Solution**:
- GPS accuracy is typically ±20-50m, causing false boundary crossings
- Increase geofence radius (try 500m+ instead of 100m)
- Increase CHECK_INTERVAL_MS to 60000 (check less frequently)
- Edit line in `guardian_firmware.ino`:
  ```cpp
  #define GEOFENCE_CHECK_INTERVAL_MS 60000  // Check every 60 seconds
  ```

### Distance Calculation Seems Wrong
**Problem**: Device shows 1000m away but looks closer, or vice versa

**Solution**:
- Double-check coordinates are correct (use maps.google.com to verify)
- GPS accuracy varies by environment (±20-50m is normal)
- Satellite geometry affects accuracy (fewer satellites = less accurate)
- Move to open area away from buildings for better accuracy
- The Haversine formula is accurate for distances up to 20km

### Firebase Write Errors
**Problem**: "Failed to log violation: Permission denied"

**Solution**:
- Update Firebase Realtime Database rules (see configuration above)
- Ensure FIREBASE_AUTH token is valid
- Check device path is under `/devices/{DEVICE_ID}`
- Verify geofence exists in Firestore before violations are created

---

## Advanced Configuration

### Adjust Check Interval
Edit in `guardian_firmware.ino`:
```cpp
#define GEOFENCE_CHECK_INTERVAL_MS 30000  // 30 seconds (default)
#define GEOFENCE_CHECK_INTERVAL_MS 60000  // 60 seconds (less frequent)
#define GEOFENCE_CHECK_INTERVAL_MS 10000  // 10 seconds (more frequent)
```

### Increase Max Geofences
Edit in `guardian_firmware.ino`:
```cpp
#define MAX_GEOFENCES 10   // Default
#define MAX_GEOFENCES 20   // Support more zones
```

### Adjust Haversine Precision
The distance calculation uses:
- Earth radius: 6,371,000 meters
- Formula: Accurate to ±0.5% for distances up to 20km
- Good enough for geofencing use case

---

## Database Schema

### Firestore
```
users/{userId}
  └─ geofences/{geofenceId}
     ├─ name: string
     ├─ latitude: number
     ├─ longitude: number
     ├─ radiusMeters: number
     ├─ enabled: boolean
     ├─ createdAt: timestamp
     └─ updatedAt: timestamp

users/{userId}
  └─ geofence_violations/{violationId}
     ├─ geofenceId: string
     ├─ name: string
     ├─ type: "entered" | "exited"
     ├─ latitude: number
     ├─ longitude: number
     ├─ distance: number (meters)
     └─ timestamp: timestamp
```

### Realtime Database
```
devices/{deviceId}
  └─ geofences/ (array)
     └─ GEO_RECORD
        ├─ id: string
        ├─ name: string
        ├─ lat: number
        ├─ lng: number
        └─ radius: number

devices/{deviceId}
  └─ geofence_violations/
     └─ {timestamp}
        ├─ geofenceId: string
        ├─ name: string
        ├─ type: string
        ├─ lat: number
        ├─ lng: number
        ├─ distance: number
        └─ timestamp: number
```

---

## Future Enhancements

- [ ] **Location Picker**: Tap to select from recent locations
- [ ] **Address Search**: Search by address name instead of coordinates
- [ ] **Polygon Geofences**: Define complex boundaries instead of just circles
- [ ] **Push Notifications**: Send device notifications on geofence violations
- [ ] **Exit Alert Timeout**: Alert guardians after device is outside for X minutes
- [ ] **Scheduled Zones**: Zones that only active during certain times
- [ ] **Geofence Groups**: Combine multiple zones (e.g., "Safe Zones")
- [ ] **Smart Notifications**: Reduce redundant notifications with smart filtering
- [ ] **Map View** (Optional): Add optional map with free service like OpenStreetMap

---

## Support & Debugging

For detailed logs, check:
1. **Serial Monitor** (Arduino IDE): Real-time firmware logs
2. **Firebase Console**: Geofence data and violations
3. **App Alerts Screen**: Historical violations logged to app
4. **Flutter DevTools**: Network requests to Firestore

---

**Version**: 1.0  
**Last Updated**: April 15, 2026  
**Status**: Fully Implemented & Tested
