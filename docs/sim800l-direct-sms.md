# SIM800L Direct SMS (Offline Alert Fallback)

> **Status:** Firmware implemented (both `guardian_firmware.ino` and `FixGPS.ino`).
> Hardware bring-up in progress. Phase 2 (P-MOSFET power gating) is future work.

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

## Final pin map

| Function | ESP32 GPIO |
|----------|-----------|
| SOS button (active LOW) | 7 |
| GPS RX | 5 |
| GPS TX | 6 |
| Status LED (active HIGH) | 3 |
| MPU6050 SDA | 11 |
| MPU6050 SCL | 10 |
| SIM800L TXD → ESP RX | 13 |
| SIM800L RXD ← ESP TX | 12 |

```cpp
constexpr uint8_t PIN_GPS_RX = 5;
constexpr uint8_t PIN_GPS_TX = 6;
constexpr uint8_t PIN_SOS    = 7;
constexpr uint8_t PIN_LED    = 3;
constexpr uint8_t PIN_SDA    = 11;
constexpr uint8_t PIN_SCL    = 10;
constexpr uint8_t PIN_SIM_RX = 13;   // SIM800L TXD -> ESP32 RX
constexpr uint8_t PIN_SIM_TX = 12;   // SIM800L RXD <- ESP32 TX
```

## Hardware BOM

| Part | Specific | Notes |
|------|----------|-------|
| SIM800L module | — | 2G-only (see "2G sunset" caveat) |
| Prepaid SIM (Globe/Smart) with SMS load | — | Holds the emergency contacts in its phonebook |
| Battery | 3.7 V LiPo, 1000 mAh | Powers SIM800L + feeds the boost |
| Charging module | **TP4056 (with DW01A protection, has `OUT+/OUT−`)** | Charges the LiPo over USB, protects against over-discharge |
| Boost converter | 3.7 V → 5 V | Steps battery up to 5 V for the ESP32 |
| Master switch | — | On the TP4056 `OUT+` line; kills boost + SIM800L together |
| Bulk capacitor | **1000 µF / 10 V, low-ESR electrolytic** (Panasonic FR/FM, Nichicon UHE, Rubycon ZLH) | Across SIM VCC–GND; prevents brownout during 2 A bursts |
| Decoupling cap (optional) | 0.1 µF (100 nF) X7R ceramic | Parallel with the electrolytic |
| P-MOSFET (Phase 2) | **AO3401** (SOT-23) | High-side switch for battery saving |
| N-MOSFET driver (Phase 2) | **2N7002** (SOT-23), or BSS138, or NPN 2N2222/BC547 | Drives the AO3401 gate |
| Pull-up resistor (Phase 2) | 10 kΩ | Gate → battery+ (keeps module OFF by default) |

## Power chain

```
USB 5 V (charger)
        │
        ▼
┌─────────────────────────────┐
│   TP4056 (with DW01A prot.) │
│  IN+  ◄──── USB 5 V         │
│  IN−  ◄──── USB GND         │
│  BAT+ ─────► LiPo (+)       │
│  BAT− ─────► LiPo (−)       │
│  OUT+ ─────► [SWITCH]       │
│  OUT− ─────► GND            │
└─────────────────────────────┘
              │
      [SWITCH] (master on/off)
              │
        ┌─────┴──────────────────────┐
        │                            │
        ▼                            ▼
   Boost VIN+  (→ 5 V → ESP32)    SIM800L VCC (3.7 V)
```

- **Switch on `OUT+`** (after TP4056, before load): switch OFF → boost + SIM800L
  off, but the battery still charges over USB.
- **SIM800L taps the switched 3.7 V line**, never the 5 V output (5 V is above the
  SIM800L's 4.4 V max and will damage it).
- **Common ground** through everything: USB GND, TP4056 `IN−`/`OUT−`/`BAT−`, LiPo −,
  boost `VIN−`/`VOUT−`, ESP32 GND, SIM800L GND, MPU6050 GND, GPS GND.

## Full wiring

```
                                 ESP32-S3 SuperMini
                              ┌─────────────────────────┐
    MPU6050                  │                         │
  ┌───────────┐              │  SDA (GPIO 11) ◄───────┼── MPU SDA
  │ SDA       ┼──────────────┤  SCL (GPIO 10) ◄───────┼── MPU SCL
  │ VCC       ┼──► 3.3V      │  GPIO 13 (RX)  ◄───────┼── SIM800L TXD
  │ GND       ┼──► GND       │  GPIO 12 (TX)  ────────┼── SIM800L RXD
  └───────────┘              │                         │
                             │  GPIO 5  (RX)  ◄───────┼── GPS TX
    GPS (GT-U8)              │  GPIO 6  (TX)  ────────┼── GPS RX
  ┌───────────┐              │  GPIO 7  (SOS) ◄───────┼── SOS button → GND
  │ TX        ┼──────────────┤                         │
  │ RX        ┼──────────────┤  GPIO 3  (LED) ──[220Ω]─┼── LED anode (cathode→GND)
  │ VCC       ┼──► 3.3V      │                         │
  │ GND       ┼──► GND       └─────────────────────────┘
  └───────────┘
```

```
   SIM800L
  ┌───────────────┐
  │ VCC ──┬───────┼──► switched 3.7 V (TP4056 OUT+, after switch)
  │       │       │
  │       └─[1000µF]─  + → VCC, − → GND (stripe side = −)
  │           │   │
  │ GND ──────┴───┼──► common GND
  │ TXD ──────────┼──► ESP32 GPIO 13 (RX)
  │ RXD ──────────┼──► ESP32 GPIO 12 (TX)
  │ RST (float)   │   ← leave unconnected
  └───────────────┘
```

### Connection table

| From | Pin | To | Pin |
|------|-----|----|-----|
| USB charger | 5 V / GND | TP4056 | IN+ / IN− |
| TP4056 | BAT+ / BAT− | LiPo | + / − |
| TP4056 | OUT+ | Switch | in |
| Switch | out | Boost VIN+ **and** SIM800L VCC | — |
| TP4056 | OUT− | Common GND | — |
| Boost | VOUT+ (5 V) | ESP32 | 5V/VIN |
| Boost | VOUT− | Common GND | — |
| SIM800L | GND | Common GND | — |
| SIM800L | TXD | ESP32 | GPIO 13 |
| SIM800L | RXD | ESP32 | GPIO 12 |
| Cap 1000 µF | + (long leg) | SIM800L | VCC |
| Cap 1000 µF | − (stripe, short leg) | SIM800L | GND |
| MPU6050 | SDA / SCL | ESP32 | GPIO 11 / GPIO 10 |
| MPU6050 | VCC / GND | ESP32 | 3.3 V / GND |
| GPS | TX / RX | ESP32 | GPIO 5 / GPIO 6 |
| GPS | VCC / GND | ESP32 | 3.3 V / GND |
| SOS button | leg 1 / leg 2 | ESP32 GPIO 7 / GND | — |
| LED | anode / cathode | GPIO 3 (via 220 Ω) / GND | — |

## SIM800L status LED

The onboard LED blinks at different rates — use it to confirm the module is ready.

| Blink | Meaning |
|-------|---------|
| Fast (several/sec) | Searching for network — not registered yet |
| Slow (~1/sec) | **Registered, ready** to send/receive SMS ✓ |
| Very slow (~1/3 sec) | Registered + GPRS data active |
| Off | No power / sleep |

On power-up it blinks fast while booting + searching, then settles to ~1/sec once
registered (5–30 s). If it **stays fast**, check: SIM seated correctly, SIM
active/no PIN, 2G signal present, antenna connected.

## Contacts strategy

The firmware cannot read the app's emergency contacts (they live in Firestore).
Instead, emergency contacts are **saved on the SIM itself** (put the SIM in a
phone → copy contacts to SIM → move it back into the SIM800L). The firmware reads
them with AT commands and SMSes **all** SIM phonebook entries.

- Standard SIM phonebook capacity: **200–250 entries**.
- Put *only* emergency contacts on the SIM — the firmware sends to all of them.
- Keeping the same contacts in the SIM and the app means each person gets one SMS
  either way (WiFi → IPROG, offline → SIM800L). Cost: keep the two lists in sync.

## Firmware changes (already applied)

```cpp
// ── Pins (section 1) ─────────────────────────────────────────────────────────
constexpr uint8_t PIN_SIM_RX = 13;   // SIM800L TXD -> ESP32 RX
constexpr uint8_t PIN_SIM_TX = 12;   // SIM800L RXD <- ESP32 TX
// (also: PIN_SOS = 7, PIN_SDA = 11, PIN_SCL = 10)

// ── UART (next to gpsSerial) ─────────────────────────────────────────────────
HardwareSerial simSerial(1);

// ── setup() ──────────────────────────────────────────────────────────────────
simSerial.begin(9600, SERIAL_8N1, PIN_SIM_RX, PIN_SIM_TX);
delay(3000);   // let the SIM800L boot and register

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
  simSerial.println("AT+CPBS=\"SM\"");       // select SIM phonebook storage
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
  sendSmsToSimContacts("[URGENT] " + deviceId + ": " + String(reason));
}
```

Geofence: SMS only on exit (`!ev.entered`), matching the IPROG behavior.

## Does it work after uploading the firmware?

The SIM800L SMS path fires **only when all of these are true**:

1. **Hardware wired** — VCC on switched 3.7 V, common GND, TXD→GPIO 13,
   RXD→GPIO 12, antenna attached, 1000 µF cap across VCC–GND.
2. **SIM inserted** — active, has SMS load, no PIN lock.
3. **Module registered** — status LED settled to ~1 blink/sec.
4. **Emergency contacts saved on the SIM** — otherwise `sendSmsToSimContacts`
   reads an empty phonebook and sends nothing.
5. **WiFi OFF** — the gate only uses the SIM800L when `WiFi.status()` is *not*
   connected. With WiFi up, alerts go through IPROG and the SIM800L stays silent.
6. **Trigger an event** — hold SOS for 3 s (or a detected fall).

So to test it: turn WiFi off (or take the device out of range), hold the SOS
button, and watch for the SMS. Watch the serial log for `+CMGS:` (sent) or
`ERROR` (failed). Keep Partition Scheme = **"Huge APP (3MB)"**.

## Caveats

- **2G sunset:** PH is decommissioning 2G by end-2026 (NTC MC 003-09-2025). The
  SIM800L is 2G-only — works in the user's area *today*, but is a time bomb. An
  LTE option is documented separately in `cellular-setup-plan.md` (Air780E, but
  for data, not direct SMS).
- **`WiFi.status()` false-positive:** it only reports router association, not
  internet reachability. Router up + WAN down → IPROG attempted and fails, SIM
  fallback never fires. Future fix: also fall back to SIM when `notifyWebhook`
  fails.
- **Manual sync:** SIM contacts and app contacts must be kept in step.
- **2 A burst vs. protection IC:** the DW01A on the TP4056 trips at ~2–3 A. The
  1000 µF cap buffers the burst so the battery sees a lower average — normally
  fine. If the SIM800L randomly resets on send, the protection may be tripping;
  try a larger cap.

## Implementation checklist

### Phase 1 — bring-up (done)

- [x] Pin map updated (SOS=7, SDA=11, SCL=10, SIM RX=13 / TX=12)
- [x] `PIN_SIM_RX` / `PIN_SIM_TX` + `HardwareSerial simSerial(1)`
- [x] `simSerial.begin(...)` + boot delay in `setup()`
- [x] `sendSmsDirect` + `sendSmsToSimContacts`
- [x] WiFi/IPROG-vs-SIM gate in `notifyEmergencyWebhook` + `notifyGeoWebhook`
- [ ] Wire hardware (TP4056 → switch → boost + SIM800L; UART to GPIO 12/13)
- [ ] Save emergency contacts to the SIM
- [ ] Test SMS with WiFi off (watch LED + serial for `+CMGS:` / `ERROR`)

### Phase 2 — battery life (P-MOSFET power gating)

- [ ] Add AO3401 + 2N7002 + 10k high-side switch (replaces the SIM800L always-on)
- [ ] Power SIM800L only when an alert fires (boot → wait registration → send → off)
- [ ] Optional: dedicated 3.7 V → 4.0 V boost if low-battery brownout is a problem
