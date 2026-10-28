# Guardian Wearable — Hardware Requirements & Power Setup

This file is the single source of truth for the device hardware: the complete
bill of materials, the current pin map, and the battery + charging setup.

---

## 1. Complete Bill of Materials (Final)

Prices are approximate Philippine-market (Shopee / Lazada) ranges and are only
a budgeting guide.

### 1.1 Core electronics (existing build)

| # | Component | Model / Spec | Qty | Interface | Approx. Price |
|---|-----------|-------------|-----|-----------|---------------|
| 1 | Microcontroller | ESP32-S3 SuperMini (ESP32-S3FH4R2, 4 MB flash) | 1 | — | ₱250–400 |
| 2 | Accelerometer / Gyro | MPU6050 (GY-521 module) | 1 | I2C (SDA=21, SCL=22) | ₱60–120 |
| 3 | GPS module | GT-U8 (GPS + BeiDou/BDS dual-mode) | 1 | UART Serial2 (RX=5, TX=6) | ₱200–400 |
| 4 | SOS button | Tactile push button | 1 | GPIO4 (active LOW, internal pull-up) | ₱5–15 |
| 5 | Status LED | Single-color LED (5 mm) | 1 | GPIO2 (via 220 Ω; replaces onboard WS2812 pixel) | ₱5 |
| 6 | LED resistor | 220 Ω, 1/4 W | 1 | in series with LED | ₱2 |
| 7 | Breadboard | 400-tie (prototyping) | 1 | — | ₱80–150 |
| 8 | Jumper wires | Dupont, M-M / M-F assortment | 1 set | — | ₱50–100 |

### 1.2 Power — battery + charging (NEW)

| # | Component | Model / Spec | Qty | Notes | Approx. Price |
|---|-----------|-------------|-----|-------|---------------|
| 9 | Battery | LiPo 3.7 V, ~1000 mAh (JST-PH 2.0 connector) — *or* 18650 3.7 V 2500–3000 mAh + holder | 1 | Single cell only | ₱150–400 |
| 10 | Charging module | TP4056 **with protection** (DW01A + 8205A), USB-C (≈17.9 × 14.1 mm) | 1 | Charges at 1 A | ₱40–80 |
| 11 | Boost converter | Mini DC-DC boost, switch-selectable 5 V / 8 V / 9 V / 12 V | 1 | 3.7 V → 5 V for the ESP32 | ₱40–80 |
| 12 | Power switch | SPST slide switch | 1 | Cuts power between charging module OUT+ and boost IN+ | ₱10–30 |
| 13 | Charging cable | USB-A → USB-C (match the charger) | 1 | For charging only | ₱50–100 |

### 1.3 Enclosure / wearables (optional but recommended)

| # | Component | Notes | Approx. Price |
|---|-----------|-------|---------------|
| 14 | Enclosure | 3D-printed case, or armband / lanyard pouch | variable |
| 15 | Hook-up wire / perfboard | For a soldered final build instead of breadboard | ₱30–100 |

> **Spares:** buy 2–3 each of the cheap parts (TP4056, mini boost, resistors, LED)
> — they are inexpensive and easy to damage while prototyping.

---

## 2. Pin Map (matches current firmware)

Firmware: `esp32_firmware/guardian_firmware/guardian_firmware.ino`

| Function | ESP32 Pin | Connected to |
|----------|-----------|--------------|
| MPU6050 SDA | GPIO8 | MPU6050 SDA |
| MPU6050 SCL | GPIO9 | MPU6050 SCL |
| GPS RX | GPIO5 (UART2 RX) | GT-U8 TX |
| GPS TX | GPIO6 (UART2 TX) | GT-U8 RX |
| SOS button | GPIO4 | button → GND |
| Status LED | GPIO2 | LED anode (220 Ω → GND) |
| Power (5 V) | 5V pin | boost converter output |
| Ground | GND | common ground (battery, boost, modules) |

> GPIO2 is free on the SuperMini (its onboard RGB + power LEDs are on GPIO48),
> so the external status LED works normally. GPIO9 (I2C SCL) is fine on the S3
> but shares a flash signal on some board variants — if I2C misbehaves, move SCL
> to GPIO7.

---

## 3. Battery & Charging Setup

### 3.1 Why a boost converter is required

The ESP32-S3 SuperMini regulates its **5 V pin** down to 3.3 V using an onboard
LDO regulator. A single LiPo/Li-ion cell is only **3.0–4.2 V**, so feeding it
straight into the 5 V pin causes brownouts and random resets. The fix is a small
**mini DC-DC boost converter** (switch-selectable 5 V / 8 V / 9 V / 12 V) that
steps the battery up to a stable **5 V**, which the onboard regulator then drops
to 3.3 V.

```
LiPo (3.7 V)  ──►  mini boost (5 V)  ──►  ESP32-S3 5V pin  ──►  LDO  ──►  3.3 V
```

The chosen module is a **mini switch-selectable boost** (5 V / 8 V / 9 V / 12 V).
It outputs ~1 A at 5 V from a 3.7 V cell — well above the device's ~350–400 mA
peak — and keeps boosting at any load (no auto power-off). **It ships switched
to 12 V by default**, so set it to 5 V and verify with a multimeter before
connecting the ESP32.

### 3.2 Battery selection

- **Pouch LiPo (~1000 mAh)** — flat and light; the recommended cell for the
  pendant. Has a JST-PH 2.0 connector (solder a JST-PH pigtail to the charger's
  `B+`/`B-`). Roughly 50 × 34 × 6 mm, ~18 g.
- **18650 cell (2500–3000 mAh)** — cylindrical, safer and easier to swap, but at
  18 × 65 mm it does **not** fit the ≈45 mm pendant case; use it only if you
  accept a bulkier belt-clip / fob form factor.

The **1000 mAh LiPo** is the sweet spot: it fits the pendant, gives ~6–8 hours,
and charges at exactly **1 C** from the 1 A charger. 800–900 mAh also works
(1.1–1.25 C); avoid 300–500 mAh with the 1 A charger (2–3 C, too hot).

Use a **single cell** only. Capacity roughly sets runtime:

| Battery | Est. runtime (WiFi TX every 2 s) |
|---------|----------------------------------|
| 1000 mAh | ~6–8 hours |
| 2000 mAh | ~12–16 hours |
| 3000 mAh (18650) | ~20–24 hours |

These are estimates — measure current draw on your exact build to confirm.

### 3.3 Charging module — TP4056 (protected variant, USB-C)

- Charges a single LiPo/Li-ion at **1 A** from a 5 V USB source.
- The **protected** version (marked `DW01A` + `8205A`) adds over-charge,
  over-discharge, and over-current protection — **use this one**, not the bare
  TP4056.
- The compact USB-C board used here (≈17.9 × 14.1 mm, 2 g) has these terminals:
  - `IN+` / `IN-` — optional 5 V input (normally the onboard USB-C port).
  - `B+` / `B-` — connect directly to the battery.
  - `OUT+` / `OUT-` — protected load output; the device draws from here.
- Key specs: 4.2 V charge termination, ~1 A charge, ~100 mA pre-charge below
  2.9 V, over-discharge cutoff ~2.4 V, over-current trip ~4 A. LEDs: red =
  charging, blue = full.

### 3.4 Wiring

```
                       ┌──────────────────────────────┐
USB-C 5V ──────────────► TP4056 (with DW01A+8205A)    │
                       │  B+ ────────► LiPo (+)       │
                       │  B- ────────► LiPo (-)       │
                       │  OUT+ ──────► mini boost IN+ │
                       │  OUT- ──────► mini boost IN- │
                       └──────────────────────────────┘

mini boost OUT+ (5 V) ──► ESP32-S3 5V pin
mini boost OUT- (GND) ──► ESP32 GND pin

ESP32 3.3V / 5V  ──► powers MPU6050 (GY-521) and GT-U8 (they have onboard regulators)
```

Power switch (required): place it in series on the positive line between
`TP4056 OUT+` and the boost `IN+` so it fully cuts power to the device when
off (the battery can still charge while the device is switched off).

### 3.5 Charging port

- **Simplest:** charge through the TP4056's own USB connector.
- **Panel-mounted port (nicer for an enclosure):** wire a USB-C breakout
  board's `VBUS` → `TP4056 IN+` and `GND` → `TP4056 IN-`, then mount the
  connector on the case.

### 3.6 Safety notes

- Use a **protected** battery *or* the protected TP4056 — do not skip the
  protection circuit.
- **Set the boost to 5 V BEFORE connecting the ESP32.** The mini boost ships
  with its selector switch on **12 V** — wiring the ESP32 in that state will
  destroy it. Switch to **5 V**, confirm ~5.0–5.1 V with a multimeter, *then*
  connect the ESP32.
- Double-check polarity — reversing the battery will damage the TP4056.
- Do not puncture, crush, or overheat LiPo cells; do not charge unattended.
- The 1 A charge rate suits a ≥1000 mAh cell (≤1 C). Do not charge a 300–500 mAh
  LiPo with it — that is 2–3 C and will overheat the cell.

### 3.7 Alternative (more efficient, advanced)

Power the ESP32 directly on its **3V3 pin** with a 3.3 V buck-boost regulator
that accepts 3.0–4.2 V input. This bypasses the onboard LDO and avoids the
double conversion loss, but you must connect to the **3V3 pin only** (never the
5V pin), and it is less forgiving if wired incorrectly. The mini boost → 5V pin
approach above is the recommended default.

---

## 4. Assembly Checklist

1. Flash and verify the firmware works over USB first.
2. Build the battery → TP4056 → mini boost → ESP32 power chain on a breadboard.
3. Switch the boost to 5 V, confirm with a multimeter, **then** connect the ESP32.
4. Confirm the device boots and pushes data to Firebase while on battery.
5. Test charging (red = charging, blue/green = done on most TP4056 boards).
6. Move to a soldered perfboard / enclosure once stable.

---

## 5. Compact Build — Smaller Module Recommendations

For the wearable build, use these modules. The chosen MCU is the **ESP32-S3
SuperMini** — the smallest board that still runs the firmware with only a
one-line I2C pin change (see below). The table lists each module and its impact.

| Component | Recommended compact model | Firmware impact |
|-----------|---------------------------|-----------------|
| Microcontroller | **ESP32-S3 SuperMini** (ESP32-S3FH4R2) | **Done** — I2C → SDA 8 / SCL 9, GPS → GPIO5/6; SOS on GPIO4, LED on GPIO2 |
| Microcontroller (alt) | ESP32-C3 SuperMini / Seeed XIAO ESP32-S3 | **More changes required** (see below) |
| Accelerometer | MPU6050 GY-521 (already small; has 3.3 V regulator + I2C pull-ups) | None |
| GPS | **GT-U8** (GPS + BeiDou/BDS dual-mode, NMEA output) | None — works with TinyGPS++ (9600 baud; verify talker ID) |
| SOS button | 6×6×5 mm tactile button | None |
| Status LED | 3 mm LED (or SMD 0805) | None |
| Charger | TP4056 with protection (USB-C) | None |
| Boost | Mini DC-DC boost (switch-selectable, set to 5 V) | None |
| Power switch | SPST slide switch (between charger OUT+ and boost IN+) | None |

> **GT-U8 (BDS) note:** this module is GPS + BeiDou. TinyGPS++ parses `GP`/`GN`
> sentences but not BeiDou's `BD`/`GB` ones. It normally emits `GP` (GPS) lines
> alongside the `BD` lines, so the firmware works — but after wiring, check the
> raw 9600-baud output: if you see `$GPGGA`/`$GPRMC` you're fine; if you see
> *only* `$BDGGA`/`$BDRMC`, reconfigure to `GP`-only (u-center / seller tool).

### ESP32-S3 SuperMini (chosen)

The ESP32-S3 SuperMini (~22.5 × 18 mm, ESP32-S3FH4R2, 4 MB flash) is a
thumb-size board with native USB. The firmware change is minimal — only I2C
moved (`SDA 21 / SCL 22` → `SDA 8 / SCL 9`), because the S3 has no GPIO22. GPS
moved to GPIO5/6 (`Serial2`), since this board only exposes GPIO1–13. SOS stays
on GPIO4, LED on GPIO2. Two setup notes:

- **No USB-to-serial chip** — enable **USB CDC On Boot** in the Arduino IDE to
  see `Serial` debug output over USB.
- **GPIO19/20 are USB D−/D+** — do not use them.

### Other small boards (more firmware changes)

- **ESP32-C3 SuperMini** (~22×18 mm, WiFi + BLE 5): single-core RISC-V, only
  two UARTs (no `HardwareSerial(2)`), and fewer GPIOs. You would move the GPS to
  `Serial1` and remap every pin — not a drop-in.
- **Seeed XIAO ESP32-S3** (thumb-size, WiFi + BLE): dual-core and has `Serial2`,
  but the pin numbering differs from the SuperMini, so you would remap the pins
  in firmware again.

> If you use one of these instead, edit the `#define` pins and the
> `HardwareSerial` line in `guardian_firmware.ino`, then re-verify I2C and UART.

---

## 6. Recommended Form Factor — Pendant Wearable

### What a pendant wearable is

A **pendant wearable** is a small, self-contained device worn around the neck on
a lanyard or cord — like a necklace or a medical-alert tag. It is the standard
form factor for personal safety and GPS trackers aimed at children, the elderly,
and people with disabilities (e.g. medical-alert pendants, and trackers such as
AngelSense or Jiobit).

For the Guardian device, this means putting the whole stack — ESP32-S3 SuperMini,
MPU6050, GT-U8 GPS, TP4056, mini boost, and LiPo — inside a small rounded case
(≈45 mm) that hangs from a lanyard.

### Why a pendant suits this device

| Factor | Pendant | Wrist (watch) |
|--------|---------|---------------|
| Fall detection (MPU6050) | On the torso near the center of mass — more accurate | Arm swings — more false positives/negatives |
| GPS fix | Antenna faces up/out | Antenna faces down |
| SOS button | Large button on the front face | Tiny side button |
| Comfort | Light on a cord; easy to hide under clothing | Bulky, thick watch head |
| Removal (child / dementia) | Harder to remove, more tamper-resistant | Easy to take off |

### Enclosure layout (front to back)

- **Front face:** large SOS button (GPIO4), status LED (GPIO2) visible through a
  light pipe or translucent window.
- **Back / top:** GPS antenna facing outward for the best satellite reception.
- **Top edge:** lanyard attachment loop (use a **breakaway clasp** for children).
- **Bottom / side:** charging port — a panel-mounted USB-C wired to the TP4056,
  or a Qi wireless-charging coil for a fully sealed case.

### Size target

- Case: ≈ 45 × 40 × 18 mm (fits the ESP32-S3 SuperMini + GT-U8 + ~1000 mAh LiPo stack).
- Weight: under ~60 g with a ~1000 mAh LiPo.

### Drawbacks (and mitigations)

- **Strangulation risk** (young children) → use a breakaway clasp on the lanyard.
- **Not as "always on" as a watch** if the wearer dislikes neck cords → fall back
  to a belt/waistband clip-on fob (same internals, different mount).
