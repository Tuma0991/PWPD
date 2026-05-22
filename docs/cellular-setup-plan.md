# Cellular-First Architecture Plan (Air780E)

## Overview

Replace hardcoded WiFi credentials with BLE provisioning for initial WiFi setup, and add an Air780E LTE module as cellular fallback so the device stays connected anywhere — on campus, playground, field trips, walking home.

## Hardware

### BOM Additions

| Part | Price (PHP) | Source |
|------|-------------|--------|
| Luat Air780E LTE Cat-1 module | ~350-500 | Shopee / Lazada |
| IoT / prepaid SIM (Globe or Smart) | ~50-100 load | Anywhere |
| 3.3V regulator (if Air780E needs dedicated 1A) | ~30 | Shopee |

### Wiring

```
ESP32                   Air780E
  GPIO13 (RX1)  ──────  TX
  GPIO12 (TX1)  ──────  RX
  3.3V          ──────  VIN
  GND           ──────  GND

ESP32                   Existing (unchanged)
  GPIO21 (SDA)  ──────  MPU6050
  GPIO22 (SCL)  ──────  MPU6050
  GPIO16 (RX2)  ──────  NEO-6M GPS TX
  GPIO17 (TX2)  ──────  NEO-6M GPS RX
  GPIO4         ──────  SOS Button
  GPIO2         ──────  LED
```

### Power Notes

The Air780E can pull up to 2A during LTE transmission bursts. If powered from ESP32's 3.3V pin, you may get brownouts. Use a dedicated 3.3V buck converter from the battery (AMS1117-3.3 or similar) capable of 1A+ for the Air780E.

## Connectivity Flow

```
Device boots
    │
    ├─ 1. Read WiFi credentials from Preferences (NVS)
    │     └─ Found? → Try WiFi
    │         ├─ Connected → Use WiFi (free)
    │         └─ Failed → Go to step 2
    │
    ├─ 2. Try cellular (Air780E)
    │     └─ Connected → Use cellular
    │
    └─ 3. Both failed → Start BLE provisioning AP
          └─ App sends new WiFi creds → Save to NVS → Reboot
```

## BLE Provisioning (First-Time WiFi Setup)

### ESP32 Side

- When stored WiFi credentials are missing or fail, ESP32 starts BLE advertising
- Advertises as "Guardian_XXXX" (XXXX = last 4 of MAC)
- Runs a BLE UART service — app connects, sends JSON: `{"ssid":"...","pass":"..."}`
- ESP32 saves to Preferences, calls `ESP.restart()`
- Libraries: built-in `BLEDevice`, `BLEUtils`, `BLEServer`, `Preferences`

### Flutter App Side

- New setup screen accessible from the dashboard
- Scans for BLE devices named "Guardian_*"
- User taps their device, enters WiFi SSID + password
- App connects to BLE UART characteristic, sends credentials
- Displays "Device connected!" confirmation
- Package: `flutter_blue_plus` (add to pubspec.yaml)

### Firebase Device Registration (Post-WiFi)

Once online (WiFi or cellular), the ESP32:
1. Sets `/devices/{deviceId}/sensors/online` = true
2. Sets `/devices/{deviceId}/meta/` with firmware version, connection type, last seen

The app reads the device list from Firebase RTDB — no pairing needed after initial BLE setup.

## Cellular Data with Air780E

### How It Works

Air780E connects to ESP32 over UART. You send AT commands. The TinyGSM library wraps all of this so your code just calls HTTP methods.

Pseudo-code with TinyGSM:

```cpp
#include <TinyGsmClient.h>

TinyGsm modem(Serial1);
TinyGsmClient client(modem);

void connectCellular() {
    modem.restart();
    modem.waitForNetwork();              // attaches to LTE
    modem.gprsConnect("internet");       // APN for Globe/Smart
}

void postToFirebase(String path, String json) {
    HttpClient http(client, "pwpd-xxx.firebaseio.com", 443);
    http.connectionKeepAlive();
    http.post(path, "application/json", json);
}
```

### Globe / Smart APNs

| Carrier | APN |
|---------|-----|
| Globe Prepaid | `http.globe.com.ph` |
| Globe M2M | `m2m.globe.com.ph` |
| Smart Prepaid | `internet` |
| Smart IoT | `iot.smart.com.ph` |

### Data Usage Estimate

Current payload (every 2s): ~200 bytes = ~5 MB/month. That fits easily on a ₱50-100 prepaid load with a 30-day data promo.

## Key ESP32 Libraries to Add

| Library | Purpose |
|---------|---------|
| `TinyGSM` | AT command wrapper for Air780E |
| `Preferences` | Store WiFi credentials in NVS |
| `BLEDevice` / `BLEUtils` / `BLEServer` (built-in) | BLE provisioning |

## Key Flutter Packages to Add

| Package | Purpose |
|---------|---------|
| `flutter_blue_plus` | BLE scanning + device provisioning |

## Implementation Phases (Future)

### Phase 1 — WiFi Persistence (no cellular yet)
- Replace `#define WIFI_SSID` / `#define WIFI_PASSWORD` with Preferences reads
- Add BLE provisioning on WiFi failure
- App: basic BLE setup screen

### Phase 2 — Air780E Cellular
- Wire Air780E, install TinyGSM
- Add cellular as fallback in `connectWiFi()` → rename to `connectNetwork()`
- Test with Globe/Smart prepaid SIM

### Phase 3 — Auto Network Selection
- `connectNetwork()` tries WiFi first, then cellular
- Reports connection type to `/devices/{id}/meta/connectionType`
- App dashboard shows WiFi vs Cellular indicator

## App UI Sketch — Device Setup Flow

```
Dashboard (no device)
    │
    ├── "Set up a device" button
    │
    ▼
Setup Screen
    ├── "Scan for devices" → BLE scan
    │   └── Shows list of "Guardian_XXXX" devices
    │       └── Tap one
    │           ├── Enter WiFi SSID
    │           ├── Enter WiFi password
    │           └── "Connect" button
    │               └── Sends over BLE
    │                   └── Success → Dashboard shows device online
    │
    └── "Already set up" → Back to Dashboard (reads from Firebase)
```
