# SIM800L Direct SMS (Offline Alert Fallback)

> **Status:** Not implemented yet. Phase 1 (hardware) can be wired now; the
> firmware changes follow. This document captures the design and a phased build
> plan.

## Goal

Give the ESP32 a **direct SMS path over cellular (2G)** so an emergency/geofence
alert still reaches the emergency contacts even when the device has **no WiFi and
no internet**. The existing IPROG path (via the Netlify `notify` function) is
kept as the primary path while the device is online.

```
WiFi connected  →  ESP32 → Netlify notify → IPROG SMS   (app's Firestore contacts)
No WiFi         →  ESP32 → SIM800L → SMS                (SIM phonebook contacts)
```

Only one path fires at a time — no duplicate SMS.

## Hardware

### BOM

| Part | Specific | Notes |
|------|----------|-------|
| SIM800L module | — | 2G-only (see "2G sunset" caveat) |
| Prepaid SIM (Globe/Smart) with SMS load | — | Holds the emergency contacts in its phonebook |
| Battery | 3.7 V LiPo, 1000 mAh | ESP32 3.3 V pin **cannot** power a SIM800L |
| Bulk capacitor | **1000 µF / 10 V, low-ESR electrolytic** (Panasonic FR/FM, Nichicon UHE, Rubycon ZLH) | Across SIM VCC–GND; prevents brownout during 2 A bursts |
| Decoupling cap (optional) | 0.1 µF (100 nF) X7R ceramic | Parallel with the electrolytic, at the module pins |
| P-MOSFET (Phase 2) | **AO3401** (SOT-23, −30 V / −4 A) | High-side switch for battery saving |
| N-MOSFET driver (Phase 2) | **2N7002** (SOT-23), or BSS138, or NPN 2N2222/BC547 | Drives the AO3401 gate |
| Pull-up resistor (Phase 2) | 10 kΩ | Gate → battery+ (keeps module OFF by default) |

### Wiring — Phase 1 (direct, for testing)

Connect directly, **no MOSFET, no resistors**. Only consequence: the SIM800L is
always powered, so it drains the 1000 mAh battery in ~2 days even idle. Unplug the
battery (or add a switch) when not testing.

```
SIM800L VCC  →  battery + (3.7 V)
SIM800L GND  →  ESP32 GND  (and battery −)
SIM800L TX   →  ESP32 GPIO 18 (RX, UART1)
SIM800L RX   →  ESP32 GPIO 17 (TX, UART1)
SIM800L RST  →  floating
[1000 µF cap] across VCC–GND, right at the module pins
```

- **UART level shifting:** SIM800L is 2.8 V logic, ESP32 drives 3.3 V. The
  textbook answer is a 1k+2k divider on the ESP32→SIM line, but most builds skip
  it and run fine. Direct is acceptable for testing.
- **No pull-up/resistors needed** in Phase 1 (the pull-up only drives the MOSFET
  gate, which comes in Phase 2).

### Wiring — Phase 2 (P-MOSFET power gating)

Adds battery saving: the ESP32 powers the SIM800L only when an alert fires.

```
Battery+ (3.7–4.2 V) ──┬──────────────────────────── SIM800L VCC
                       │
                     [10k]  (pull-up: keeps it OFF by default)
                       │
                       ├── S (source)
                    AO3401   [P-MOSFET]
                       ├── D (drain) ──────────────── SIM800L VCC
                       │
                       └── G (gate) ───┬─── Drain of 2N7002 (N-MOSFET)
                                       │
                                    [2N7002]
                                       ├── Source ─── GND
                                       └── Gate ────── ESP32 GPIO
```

Logic: GPIO HIGH → 2N7002 on → pulls AO3401 gate to GND → AO3401 on → powered.
GPIO LOW → 2N7002 off → gate floats up to battery+ via 10k → AO3401 off.

Why the extra N-MOSFET: the battery tops out at 4.2 V while the GPIO is 3.3 V —
that 0.9 V gap means the GPIO alone can't reliably turn the P-MOSFET *off*.

### Power notes

- SIM800L pulls ~2 A in short (~0.5 ms) transmit bursts. The 1000 µF cap is the
  local reservoir that supplies that burst; without it the module resets mid-send.
- Left powered on, SIM800L idles at ~20–30 mA. On a 1000 mAh battery that's
  ~40 h to dead — so Phase 2 (P-MOSFET) is required for any real, wearable use.
- **Battery headroom:** SIM800L operates 3.4–4.4 V. A LiPo is 4.2 V full →
  3.0 V empty, and sags under load, so the module browns out below ~3.5 V
  (roughly the bottom third of the cell). For an emergency-only device that
  powers the SIM800L for ~10–15 s only on alert, that's acceptable. If it proves
  unreliable on a low battery, add a boost converter (3.7 V → 4.0 V) between the
  battery and the MOSFET.

### Current firmware pin usage (unchanged)

GPS on UART2 (RX=5 / TX=6), SOS=4, LED=3, MPU6050 I2C (SDA=9 / SCL=8). **UART1
(`Serial1`) is free** — GPIO 17/18 are the ESP32-S3 native UART1 pins. Avoid
strapping pins 0, 3, 45, 46 and USB pins 43/44.

## Contacts strategy

The firmware cannot read the app's emergency contacts (they live in Firestore).
Instead, emergency contacts are **saved on the SIM itself** (put the SIM in a
phone → copy contacts to SIM → move it back into the SIM800L). The firmware reads
them with AT commands and SMSes **all** SIM phonebook entries.

- Standard SIM phonebook capacity: **200–250 entries**.
- No "emergency" flag exists on SIM contacts — put *only* emergency contacts on
  the SIM, and the firmware sends to all of them.
- Keeping the same contacts in both the SIM and the app is expected. Because only
  one path fires at a time (WiFi → IPROG, offline → SIM800L), no one is double-texted.
  Cost: the two lists must be kept in sync manually.

## Firmware changes (`guardian_firmware.ino`)

```cpp
// ── Pins + UART (add next to PIN_GPS_RX / gpsSerial) ──────────────────────────
constexpr uint8_t PIN_SIM_RX = 18;   // SIM800L TX -> ESP32 RX
constexpr uint8_t PIN_SIM_TX = 17;   // SIM800L RX <- ESP32 TX
HardwareSerial simSerial(1);

// in setup(): simSerial.begin(9600, SERIAL_8N1, PIN_SIM_RX, PIN_SIM_TX);

// ── Send one SMS ──────────────────────────────────────────────────────────────
static void sendSmsDirect(const char* phone, const String& body) {
  simSerial.println("AT+CMGF=1");            // text mode
  delay(300);
  simSerial.print("AT+CMGS=\"");
  simSerial.print(phone);
  simSerial.println("\"");
  delay(300);
  simSerial.print(body);
  simSerial.write(0x1A);                     // Ctrl+Z = send
  delay(5000);
}

// ── Read all SIM phonebook entries and SMS each one ───────────────────────────
static void sendSmsToSimContacts(const String& body) {
  simSerial.println("AT+CPBS=\"SM\"");       // select SIM storage
  delay(300);
  simSerial.println("AT+CPBR=1,50");         // read entries 1..50
  delay(600);
  unsigned long t = millis() + 3000;
  while (millis() < t) {
    if (!simSerial.available()) continue;
    String line = simSerial.readStringUntil('\n');
    line.trim();
    if (line.startsWith("+CPBR:")) {
      int q1 = line.indexOf('"');
      int q2 = line.indexOf('"', q1 + 1);
      if (q1 >= 0 && q2 > q1) {
        String num = line.substring(q1 + 1, q2);
        sendSmsDirect(num.c_str(), body);
      }
    }
    if (line == "OK" || line == "ERROR") break;
  }
}
```

### Hybrid gate (in `notifyEmergencyWebhook` / `notifyGeoWebhook`)

```cpp
if (WiFi.status() == WL_CONNECTED) {
  notifyWebhook("emergency", body);                        // IPROG via Netlify
} else {
  sendSmsToSimContacts("[URGENT] " + String(deviceId) + ": " + String(reason));
}
```

Numbers stored as `09…`, `+63…`, or `63…` all send fine via `AT+CMGS` (no
normalization needed for a PH SIM).

## Caveats

- **2G sunset:** PH is decommissioning 2G by end-2026 (NTC MC 003-09-2025). The
  SIM800L is 2G-only — works in the user's area *today*, but is a time bomb. An
  LTE option is documented separately in `cellular-setup-plan.md` (Air780E, but
  for data, not direct SMS).
- **`WiFi.status()` false-positive:** it only reports router association, not
  internet reachability. If the router is up but the WAN is down, the IPROG path
  is attempted and fails, and the SIM fallback never fires. Possible future fix:
  also fall back to SIM when `notifyWebhook` fails.
- **Manual sync:** SIM contacts and app contacts must be kept in step.

## Implementation checklist

### Phase 1 — hardware bring-up (direct + cap)

- [ ] Wire SIM800L directly (VCC → battery, GND → GND, TX/RX → GPIO 18/17)
- [ ] Add 1000 µF / 10 V low-ESR cap across VCC–GND (optional 100 nF in parallel)
- [ ] Save emergency contacts to the SIM via a phone
- [ ] Add `PIN_SIM_RX` / `PIN_SIM_TX` + `HardwareSerial simSerial(1)`
- [ ] Init `simSerial` in `setup()`
- [ ] Add `sendSmsDirect` + `sendSmsToSimContacts`
- [ ] Add WiFi/IPROG-vs-SIM gate in `notifyEmergencyWebhook` + `notifyGeoWebhook`
- [ ] Test SMS with WiFi off (watch serial for `+CMGS:` / `ERROR`)
- [ ] Keep Partition Scheme = "Huge APP (3MB)" (flash was at 101% without it)

### Phase 2 — battery life (P-MOSFET power gating)

- [ ] Add AO3401 + 2N7002 + 10k high-side switch (wiring above)
- [ ] Power SIM800L on only when an alert fires (boot → wait registration → send → off)
- [ ] Optional: add 3.7 V → 4.0 V boost converter if low-battery brownout is a problem
